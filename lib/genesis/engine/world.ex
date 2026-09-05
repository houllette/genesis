defmodule Genesis.Engine.World do
  @moduledoc "World ownership, scoped grants and orchestration; persistent mode revalidates durable membership."
  use GenServer
  alias Genesis.Core.{Scope, State}

  alias Genesis.Engine.{
    CommandCoordinator,
    DurableWorld,
    PublicationCoordinator,
    Session,
    TransferCoordinator,
    Zone
  }

  alias Genesis.Engine.Supervisor, as: Lookup
  alias Genesis.Persistence.{Access, Authority, Incorporation, Snapshot, Snapshots, Transfers}
  alias Genesis.Repo

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts),
    do:
      GenServer.start_link(__MODULE__, opts,
        name:
          Lookup.via(
            Keyword.fetch!(opts, :registry),
            {:world, Keyword.fetch!(opts, :world_id)}
          )
      )

  @spec admit(world :: GenServer.server(), scene :: Genesis.Core.State.t(), opts :: keyword()) ::
          {:ok, pid()} | {:error, atom()}
  def admit(world, scene, opts \\ []), do: GenServer.call(world, {:admit, scene, opts})

  @spec grant(world :: GenServer.server(), principal :: map()) ::
          {:ok, reference()} | {:error, atom()}
  def grant(world, principal), do: GenServer.call(world, {:grant, principal})
  @spec revoke(world :: GenServer.server(), token :: reference()) :: :ok | {:error, atom()}
  def revoke(world, token), do: GenServer.call(world, {:revoke, token})

  @spec authorize(
          world :: GenServer.server(),
          token :: reference(),
          scope :: Scope.t(),
          zone :: String.t()
        ) :: {:ok, map()} | {:error, atom()}
  def authorize(world, token, scope, zone),
    do: GenServer.call(world, {:authorize, token, scope, zone}, 2000)

  @spec attach(
          world :: GenServer.server(),
          token :: reference(),
          zone :: pid(),
          consumer :: pid()
        ) :: {:ok, pid()} | {:error, term()}
  def attach(world, token, zone, consumer \\ self()),
    do: GenServer.call(world, {:attach, token, zone, consumer})

  @spec pause(world :: GenServer.server(), scope :: Scope.t()) :: :ok | {:error, atom()}
  def pause(world, scope), do: GenServer.call(world, {:status, scope, :paused})
  @spec resume(world :: GenServer.server(), scope :: Scope.t()) :: :ok | {:error, atom()}
  def resume(world, scope), do: GenServer.call(world, {:status, scope, :active})

  @spec identity(world :: GenServer.server()) :: {String.t(), non_neg_integer()}
  def identity(world), do: GenServer.call(world, :identity)

  @spec mode(world :: GenServer.server()) :: :postgres | nil
  def mode(world), do: GenServer.call(world, :mode)

  @impl true
  def init(opts) do
    if Keyword.get(opts, :storage) == :postgres do
      {:ok, :recovered} = Incorporation.recover(Keyword.fetch!(opts, :world_id))
      {:ok, :recovered} = Transfers.recover(Keyword.fetch!(opts, :world_id))
    end

    if Keyword.get(opts, :storage) == :postgres,
      do: Phoenix.PubSub.subscribe(Genesis.PubSub, "world:" <> Keyword.fetch!(opts, :world_id))

    if observer = Keyword.get(opts, :observer),
      do: send(observer, {:genesis_world_started, self()})

    {:ok,
     %{
       owner: Keyword.fetch!(opts, :owner),
       world_id: Keyword.fetch!(opts, :world_id),
       generation: Keyword.fetch!(opts, :generation),
       registry: Keyword.fetch!(opts, :registry),
       workers: Keyword.fetch!(opts, :workers),
       storage: Keyword.get(opts, :storage),
       zone_opts: Keyword.get(opts, :zone_opts, []),
       previews: %{},
       zones: %{},
       grants: %{},
       sessions: %{},
       transfers: %{},
       publication: nil,
       commands: %{},
       claims: %{},
       statuses: %{},
       window: nil
     }}
  end

  @impl true
  def handle_call(:identity, _from, state),
    do: {:reply, {state.world_id, state.generation}, state}

  def handle_call(:mode, _from, state), do: {:reply, state.storage, state}

  def handle_call({:durable, _scope, _command}, _from, %{publication: publication} = state)
      when not is_nil(publication), do: {:reply, {:error, :publication_busy}, state}

  def handle_call(
        {:durable, scope, {:incorporate, preview, request}},
        from,
        %{storage: :postgres} = state
      ) do
    case Incorporation.receipt(scope, state.world_id, preview, request) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      :new -> begin_publication(state, scope, preview, request, from)
      error -> {:reply, error, state}
    end
  end

  def handle_call({:publication_authorized, worker, operation}, _from, state) do
    allowed = match?(%{pid: ^worker, operation: %{id: ^operation}}, state.publication)
    {:reply, if(allowed, do: :ok, else: {:error, :unauthorized}), state}
  end

  def handle_call({:command_authorized, worker}, {zone, _}, state) do
    allowed =
      Enum.any?(state.commands, fn {_ref, entry} -> entry.pid == worker and entry.zone == zone end)

    {:reply, if(allowed, do: :ok, else: {:error, :unauthorized}), state}
  end

  def handle_call({:locate_session, _token}, _from, %{publication: publication} = state)
      when not is_nil(publication), do: {:reply, {:error, :publication_busy}, state}

  def handle_call(
        {:durable, scope, {:travel, exp, actor, token, request}},
        from,
        %{storage: :postgres} = state
      ) do
    if map_size(state.transfers) < 4 do
      case Transfers.begin(scope, state.world_id, exp, actor, token, request) do
        {:ok, {:done, result}} -> {:reply, {:ok, result}, state}
        {:ok, {:prepared, op}} -> start_transfer(state, scope, op, from)
        error -> {:reply, error, state}
      end
    else
      {:reply, {:error, :transfer_busy}, state}
    end
  end

  def handle_call({:transfer_authorized, worker, operation}, _from, state) do
    allowed =
      Enum.any?(state.transfers, fn {_ref, entry} ->
        entry.pid == worker and entry.operation.id == operation
      end)

    {:reply, if(allowed, do: :ok, else: {:error, :unauthorized}), state}
  end

  def handle_call({:locate_session, token}, {caller, _}, %{storage: :postgres} = state) do
    with true <-
           Enum.any?(state.sessions, fn {_ref, entry} -> entry == %{pid: caller, token: token} end),
         %{} = principal <- state.grants[token],
         {:ok, current} <- Authority.current(principal),
         %Snapshot{} = snapshot <- Repo.get(Snapshot, current.snapshot_id),
         :ok <- Transfers.accessible(snapshot.id),
         {:ok, zone, state} <- DurableWorld.zone(state, snapshot) do
      {:reply, {:ok, zone}, %{state | grants: Map.put(state.grants, token, current)}}
    else
      {:error, _} = error -> {:reply, error, state}
      _ -> {:reply, {:error, :unauthorized}, state}
    end
  end

  def handle_call(
        {:durable, scope, command},
        {caller, _tag} = from,
        %{storage: :postgres} = state
      ) do
    if map_size(state.commands) < 16 do
      case DurableWorld.call(state, scope, command, caller) do
        {:delegate, zone, operation, state} -> start_command(state, zone, operation, from)
        reply -> reply
      end
    else
      {:reply, {:error, :capacity_limit}, state}
    end
  end

  def handle_call({:authorize, token, scope, zone}, _from, state),
    do: {:reply, authorization(state, token, scope, zone), state}

  def handle_call({:attach, token, zone, consumer}, {caller, _tag}, state)
      when caller == consumer do
    if attachable?(state, token, zone) do
      result =
        DynamicSupervisor.start_child(
          state.workers,
          {Session, world: self(), zone: zone, token: token, consumer: consumer}
        )

      {:reply, result, state}
    else
      {:reply, {:error, :unauthorized}, state}
    end
  end

  def handle_call(_request, _from, %{storage: :postgres} = state),
    do: {:reply, {:error, :unsupported_operation}, state}

  def handle_call(request, {caller, _tag}, %{owner: caller} = state),
    do: owner_call(request, state)

  def handle_call(_request, _from, state), do: {:reply, {:error, :unauthorized}, state}

  @impl true
  def handle_info({:publication_done, pid, result}, %{publication: %{pid: pid} = entry} = state) do
    if not match?({:ok, _}, result), do: recover_publication(state)
    GenServer.reply(entry.from, result)
    Process.demonitor(entry.monitor, [:flush])

    previews =
      if match?({:ok, _}, result),
        do: Map.delete(state.previews, entry.preview_key),
        else: state.previews

    {:noreply, %{state | publication: nil, previews: previews}}
  end

  def handle_info({:command_done, pid, result}, state) do
    case Enum.find(state.commands, fn {_ref, entry} -> entry.pid == pid end) do
      {ref, entry} ->
        GenServer.reply(entry.from, result)
        Process.demonitor(ref, [:flush])
        {:noreply, %{state | commands: Map.delete(state.commands, ref)}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state)
      when is_map_key(state.commands, ref) do
    entry = state.commands[ref]
    DynamicSupervisor.terminate_child(state.workers, entry.zone)
    GenServer.reply(entry.from, {:error, :command_interrupted})
    {:noreply, %{state | commands: Map.delete(state.commands, ref)}}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{publication: %{monitor: ref} = entry} = state
      ) do
    recover_publication(state)
    GenServer.reply(entry.from, {:error, :publication_interrupted})
    {:noreply, %{state | publication: nil}}
  end

  def handle_info({:transfer_done, pid, result}, state) do
    case Enum.find(state.transfers, fn {_ref, entry} -> entry.pid == pid end) do
      {ref, entry} ->
        if not match?({:ok, _}, result), do: recover_transfer(state, entry)
        notify_transfer_sessions(state, entry.operation)
        GenServer.reply(entry.from, result)
        Process.demonitor(ref, [:flush])
        {:noreply, %{state | transfers: Map.delete(state.transfers, ref)}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state)
      when is_map_key(state.transfers, ref) do
    entry = state.transfers[ref]
    recover_transfer(state, entry)
    GenServer.reply(entry.from, {:error, :transfer_interrupted})
    {:noreply, %{state | transfers: Map.delete(state.transfers, ref)}}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    zones =
      Map.new(state.zones, fn {key, entry} ->
        {key, if(entry.monitor == monitor, do: %{entry | pid: nil}, else: entry)}
      end)

    {session, sessions} = Map.pop(state.sessions, monitor)
    token = if is_map(session), do: session.token, else: session

    {:noreply,
     %{state | zones: zones, sessions: sessions, grants: Map.delete(state.grants, token)}}
  end

  def handle_info(
        {:world_changed, world, _cursor},
        %{world_id: world, storage: :postgres} = state
      ) do
    grants =
      Map.reject(state.grants, fn {token, principal} ->
        case Authority.current(principal) do
          {:ok, _current} ->
            false

          _ ->
            notify_zones(state, {:revoked, token})
            true
        end
      end)

    {:noreply, %{state | grants: grants}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp owner_call({:admit, %State{scope: %Scope{}} = scene, opts}, state) do
    key = {Scope.key(scene.scope), scene.zone_id}

    cond do
      not admissible?(state, scene, opts) -> {:reply, {:error, :invalid_scope}, state}
      Map.has_key?(state.zones, key) -> existing_zone(state.zones[key], state)
      map_size(state.zones) >= 16 -> {:reply, {:error, :capacity_limit}, state}
      conflict?(state, scene) -> {:reply, {:error, :claimed}, state}
      true -> start_zone(state, scene, opts, key)
    end
  end

  defp owner_call({:grant, principal}, state) do
    if principal?(principal, state) and map_size(state.grants) < 256 do
      token = make_ref()
      {:reply, {:ok, token}, %{state | grants: Map.put(state.grants, token, principal)}}
    else
      {:reply, {:error, :invalid_principal}, state}
    end
  end

  defp owner_call({:revoke, token}, state) do
    notify_zones(state, {:revoked, token})
    {:reply, :ok, %{state | grants: Map.delete(state.grants, token)}}
  end

  defp owner_call({:status, %Scope{} = scope, status}, state) when status in [:active, :paused] do
    key = Scope.key(scope)

    if Map.has_key?(state.statuses, key) do
      notify_zones(state, {:status_changed, scope, status})
      {:reply, :ok, %{state | statuses: Map.put(state.statuses, key, status)}}
    else
      {:reply, {:error, :unavailable}, state}
    end
  end

  defp owner_call(_request, state), do: {:reply, {:error, :unsupported_operation}, state}

  defp admissible?(state, scene, opts),
    do:
      Scope.valid?(scene.scope) and scene.scope.world_id == state.world_id and
        scene.scope.generation == state.generation and
        scene.scope.kind in [:experience, :published, :rehearsal] and
        Keyword.get(opts, :start_offset, 0) == 0 and
        (is_nil(state.window) or scene.scope.kind != :experience or
           scene.scope.window_id == state.window)

  defp claim_keys(scene) do
    keys =
      [{:zone, scene.zone_id}] ++
        Enum.map(Map.keys(scene.actors), &{:actor, &1}) ++
        Enum.map(Map.keys(scene.items), &{:item, &1})

    namespace =
      if scene.scope.kind == :experience, do: :experience_assignment, else: Scope.key(scene.scope)

    Enum.map(keys, &{namespace, &1})
  end

  defp conflict?(state, scene),
    do:
      Enum.any?(claim_keys(scene), fn key ->
        Map.has_key?(state.claims, key) and
          state.claims[key] != {Scope.key(scene.scope), scene.zone_id}
      end)

  defp existing_zone(%{pid: nil}, state), do: {:reply, {:error, :state_lost}, state}
  defp existing_zone(%{pid: pid}, state), do: {:reply, {:ok, pid}, state}

  defp start_zone(state, scene, opts, key) do
    opts =
      Keyword.merge(opts,
        world: self(),
        scene: scene,
        name: Lookup.via(state.registry, {:zone, key})
      )

    case DynamicSupervisor.start_child(state.workers, {Zone, opts}) do
      {:ok, pid} ->
        entry = %{pid: pid, monitor: Process.monitor(pid), actors: Map.keys(scene.actors)}

        state = %{
          state
          | zones: Map.put(state.zones, key, entry),
            statuses: Map.put_new(state.statuses, Scope.key(scene.scope), :active)
        }

        state = claim(state, scene)
        {:reply, {:ok, pid}, state}

      error ->
        {:reply, error, state}
    end
  end

  defp claim(state, scene),
    do: %{
      state
      | window:
          if(scene.scope.kind == :experience, do: scene.scope.window_id, else: state.window),
        claims:
          Enum.reduce(
            claim_keys(scene),
            state.claims,
            &Map.put(&2, &1, {Scope.key(scene.scope), scene.zone_id})
          )
    }

  defp principal?(
         %{
           id: id,
           campaign_id: campaign,
           actor_id: actor,
           role: role,
           scope: %Scope{} = scope,
           zone_id: zone
         } = principal,
         state
       ) do
    key = {Scope.key(scope), zone}

    map_size(principal) == 6 and Scope.id?(id) and Scope.id?(campaign) and
      role in [:gm, :player, :spectator] and
      Map.has_key?(state.zones, key) and actor in state.zones[key].actors
  end

  defp principal?(_principal, _state), do: false

  defp attachable?(state, token, zone) do
    case state.grants[token] do
      %{scope: scope, zone_id: zone_id} ->
        match?(%{pid: ^zone}, state.zones[{Scope.key(scope), zone_id}]) and is_pid(zone)

      _ ->
        false
    end
  end

  defp authorization(%{storage: :postgres} = state, token, scope, zone) do
    with %{scope: ^scope} = principal <- state.grants[token],
         {:ok, %{zone_id: ^zone} = current} <- Authority.current(principal) do
      {:ok, current}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authorization(state, token, scope, zone) do
    case state.grants[token] do
      %{scope: ^scope, zone_id: ^zone} = principal ->
        {:ok, Map.put(principal, :status, state.statuses[Scope.key(scope)])}

      _ ->
        {:error, :unauthorized}
    end
  end

  defp start_transfer(state, scope, op, from) do
    with {:ok, source, state} <-
           DurableWorld.zone(state, Repo.get!(Snapshot, op.source_snapshot_id)),
         {:ok, destination, state} <-
           DurableWorld.zone(state, Repo.get!(Snapshot, op.destination_snapshot_id)),
         {:ok, pid} <-
           DynamicSupervisor.start_child(
             state.workers,
             {TransferCoordinator,
              world: self(),
              scope: scope,
              operation: op,
              source: source,
              destination: destination,
              opts: state.zone_opts}
           ) do
      entry = %{pid: pid, operation: op, from: from, zones: [source, destination]}
      {:noreply, %{state | transfers: Map.put(state.transfers, Process.monitor(pid), entry)}}
    else
      error ->
        # A partial start never installed candidate state. All caches refresh
        # from durable snapshots, but terminate any affected cache before unlock.
        stop_transfer_zones(state, op)
        {:ok, :recovered} = Transfers.recover(state.world_id, op.id)
        {:reply, error, state}
    end
  end

  defp start_command(state, zone, command, from) do
    case DynamicSupervisor.start_child(
           state.workers,
           {CommandCoordinator, world: self(), zone: zone, command: command}
         ) do
      {:ok, pid} ->
        entry = %{pid: pid, zone: zone, from: from}
        {:noreply, %{state | commands: Map.put(state.commands, Process.monitor(pid), entry)}}

      error ->
        {:reply, error, state}
    end
  end

  defp begin_publication(state, scope, preview, request, from) do
    with {:ok, user} <- Access.user_id(scope),
         %{} = prepared <- state.previews[{user, preview}],
         {:ok, op} <- Incorporation.begin(scope, state.world_id, prepared, request) do
      start_publication(state, scope, prepared, op, from, {user, preview})
    else
      {:error, _} = error -> {:reply, error, state}
      _ -> {:reply, {:error, :stale_preview}, state}
    end
  end

  defp start_publication(state, scope, prepared, op, from, key) do
    started =
      Enum.reduce_while(prepared.zones, {:ok, state, []}, fn zone, {:ok, current, zones} ->
        case DurableWorld.zone(current, zone.published_snapshot) do
          {:ok, pid, next} -> {:cont, {:ok, next, zones ++ [{pid, zone.candidate}]}}
          error -> {:halt, error}
        end
      end)

    with {:ok, state, zones} <- started,
         {:ok, pid} <-
           DynamicSupervisor.start_child(
             state.workers,
             {PublicationCoordinator,
              world: self(), scope: scope, operation: op, zones: zones, opts: state.zone_opts}
           ) do
      entry = %{
        pid: pid,
        monitor: Process.monitor(pid),
        operation: op,
        zones: zones,
        from: from,
        preview_key: key
      }

      {:noreply, %{state | publication: entry}}
    else
      error ->
        stop_publication_zones(state, op)
        {:ok, :recovered} = Incorporation.recover(state.world_id)
        {:reply, error, state}
    end
  end

  defp recover_publication(state) do
    stop_publication_zones(state, state.publication.operation)
    {:ok, :recovered} = Incorporation.recover(state.world_id)
  end

  defp stop_publication_zones(state, op) do
    for zone <- op.manifest["zones"] do
      row = Repo.get!(Snapshot, zone["published_snapshot_id"])
      {:ok, scene} = Snapshots.load(row)
      name = Lookup.via(state.registry, {:zone, {Scope.key(scene.scope), scene.zone_id}})
      if pid = GenServer.whereis(name), do: DynamicSupervisor.terminate_child(state.workers, pid)
    end
  end

  defp recover_transfer(state, entry) do
    Enum.each(entry.zones, &DynamicSupervisor.terminate_child(state.workers, &1))
    {:ok, :recovered} = Transfers.recover(state.world_id, entry.operation.id)
  end

  defp notify_transfer_sessions(state, op) do
    for {_ref, %{pid: pid, token: token}} <- state.sessions do
      case state.grants[token] do
        %{snapshot_id: id} when id in [op.source_snapshot_id, op.destination_snapshot_id] ->
          send(pid, {:travel_changed, self()})

        _ ->
          :ok
      end
    end
  end

  defp stop_transfer_zones(state, op) do
    for id <- [op.source_snapshot_id, op.destination_snapshot_id] do
      row = Repo.get!(Snapshot, id)
      {:ok, scene} = Snapshots.load(row)
      name = Lookup.via(state.registry, {:zone, {Scope.key(scene.scope), scene.zone_id}})
      if pid = GenServer.whereis(name), do: DynamicSupervisor.terminate_child(state.workers, pid)
    end
  end

  defp notify_zones(state, message),
    do:
      Enum.each(state.zones, fn
        {_key, %{pid: nil}} -> :ok
        {_key, %{pid: pid}} -> send(pid, {self(), message})
      end)
end
