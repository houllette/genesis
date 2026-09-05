defmodule Genesis.Engine.World do
  @moduledoc "World ownership, scoped grants and orchestration; persistent mode revalidates durable membership."
  use GenServer
  alias Genesis.Core.{Scope, State}
  alias Genesis.Engine.{DurableWorld, Session, Zone}
  alias Genesis.Engine.Supervisor, as: Lookup
  alias Genesis.Persistence.Authority

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
       claims: %{},
       statuses: %{},
       window: nil
     }}
  end

  @impl true
  def handle_call(:identity, _from, state),
    do: {:reply, {state.world_id, state.generation}, state}

  def handle_call(:mode, _from, state), do: {:reply, state.storage, state}

  def handle_call({:durable, scope, command}, {caller, _tag}, %{storage: :postgres} = state),
    do: DurableWorld.call(state, scope, command, caller)

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
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    zones =
      Map.new(state.zones, fn {key, entry} ->
        {key, if(entry.monitor == monitor, do: %{entry | pid: nil}, else: entry)}
      end)

    {token, sessions} = Map.pop(state.sessions, monitor)

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
    case state.grants[token] do
      %{scope: ^scope, zone_id: ^zone} = principal -> Authority.current(principal)
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

  defp notify_zones(state, message),
    do:
      Enum.each(state.zones, fn
        {_key, %{pid: nil}} -> :ok
        {_key, %{pid: pid}} -> send(pid, {self(), message})
      end)
end
