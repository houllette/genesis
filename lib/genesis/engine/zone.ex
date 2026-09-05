defmodule Genesis.Engine.Zone do
  @moduledoc "Single scoped writer. Persistent mode commits snapshots, receipts and effects before acknowledgement."
  use GenServer, restart: :temporary
  alias Genesis.Core.{LocalAction, Scene, Scope, State}
  alias Genesis.Engine.{Draws, World}
  alias Genesis.Persistence.{Actions, Control, Curation, Snapshot, Snapshots}
  alias Genesis.Repo
  alias Genesis.Time.Clock

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  @spec bind(zone :: pid(), token :: reference()) :: :ok | {:error, atom()}
  def bind(zone, token), do: GenServer.call(zone, {:bind, token}, 3000)
  @spec detach(zone :: pid()) :: :ok
  def detach(zone), do: GenServer.call(zone, :detach)
  @spec view(zone :: pid()) :: {:ok, map()} | {:error, atom()}
  def view(zone), do: GenServer.call(zone, :view, 3000)
  @spec submit(zone :: pid(), request :: map()) :: {:ok, map()} | {:error, atom()}
  def submit(zone, request), do: GenServer.call(zone, {:submit, request}, 3000)

  @spec propose(zone :: pid(), id :: String.t(), intent :: map()) ::
          {:ok, map()} | {:error, atom()} | {:clarify, atom()}
  def propose(zone, id, intent), do: GenServer.call(zone, {:propose, id, intent}, 3000)

  @spec confirm(zone :: pid(), id :: String.t(), proposal :: String.t()) ::
          {:ok, map()} | {:error, atom()}
  def confirm(zone, id, proposal), do: GenServer.call(zone, {:confirm, id, proposal}, 3000)

  @impl true
  def init(opts) do
    {:ok,
     %{
       scene: Keyword.fetch!(opts, :scene),
       world: Keyword.fetch!(opts, :world),
       clock: Keyword.get(opts, :clock, Clock.system()),
       draw: Keyword.get(opts, :draw, &Draws.roll/1),
       bindings: %{},
       disconnected: MapSet.new(),
       receipts: %{},
       proposals: %{},
       limit: Keyword.get(opts, :receipt_limit, 1000),
       storage: Keyword.get(opts, :storage),
       storage_opts: Keyword.take(opts, [:clock, :fault])
     }}
  end

  @impl true
  def handle_call({:bind, token}, {caller, _tag}, state) do
    with {:ok, principal} <-
           World.authorize(state.world, token, state.scene.scope, state.scene.zone_id),
         {:ok, _projection} <- State.view(state.scene, principal),
         true <- map_size(state.bindings) < 64,
         false <- Map.has_key?(state.bindings, caller) do
      binding = %{
        token: token,
        actor_id: principal.actor_id,
        monitor: Process.monitor(caller),
        pending: false
      }

      {:reply, :ok,
       %{
         state
         | bindings: Map.put(state.bindings, caller, binding),
           disconnected: MapSet.delete(state.disconnected, principal.actor_id)
       }}
    else
      _ -> {:reply, {:error, :unauthorized}, state}
    end
  end

  def handle_call(:detach, {caller, _tag}, state), do: {:reply, :ok, unbind(state, caller)}

  def handle_call(:install_committed, {world, _tag}, %{world: world, storage: storage} = state)
      when not is_nil(storage) do
    {:ok, state} = refresh(state)
    {:reply, :ok, notify(state)}
  end

  def handle_call(
        {:control, scope, action, revision, request},
        {world, _tag},
        %{world: world, storage: storage} = state
      )
      when not is_nil(storage) do
    with {:ok, state} <- refresh(state),
         {:ok, changed} <-
           Control.change(
             scope,
             storage.snapshot_id,
             state.scene,
             action,
             revision,
             request,
             state.storage_opts
           ) do
      {:reply, {:ok, changed.result}, notify(%{state | scene: changed.scene})}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:curate, scope, operation},
        {world, _tag},
        %{world: world, storage: storage} = state
      )
      when not is_nil(storage) do
    with {:ok, state} <- refresh(state),
         {:ok, changed} <- Curation.edit(scope, storage.snapshot_id, state.scene, operation) do
      {:reply, {:ok, changed.result}, notify(%{state | scene: changed.scene})}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(request, {caller, _tag}, state) do
    with %{token: token} <- state.bindings[caller],
         {:ok, principal} <-
           World.authorize(state.world, token, state.scene.scope, state.scene.zone_id),
         {:ok, state} <- refresh(state) do
      state = sync_status(state, principal.status)
      authorized_call(request, caller, principal, state)
    else
      _ -> {:reply, {:error, :unauthorized}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, pid, _reason}, state) do
    if match?(%{monitor: ^monitor}, state.bindings[pid]),
      do: {:noreply, unbind(state, pid)},
      else: {:noreply, state}
  end

  def handle_info({world, {:revoked, token}}, %{world: world} = state) do
    revoked = Enum.filter(state.bindings, fn {_pid, binding} -> binding.token == token end)

    state =
      Enum.reduce(revoked, state, fn {pid, _binding}, current ->
        send(pid, {:revoked, self()})
        unbind(current, pid)
      end)

    {:noreply, state}
  end

  def handle_info(
        {world, {:status_changed, scope, status}},
        %{world: world, scene: %{scope: scope}} = state
      ),
      do: {:noreply, state |> sync_status(status) |> notify()}

  def handle_info(_message, state), do: {:noreply, state}

  defp authorized_call(:view, caller, principal, state) do
    reply = projection(state, principal)
    {:reply, reply, put_in(state.bindings[caller].pending, false)}
  end

  defp authorized_call({:propose, _id, _intent}, _caller, %{role: :spectator}, state),
    do: {:reply, {:error, :read_only}, state}

  defp authorized_call({:propose, _id, _intent}, _caller, %{status: :paused}, state),
    do: {:reply, {:error, :paused}, state}

  defp authorized_call({:propose, id, intent}, _caller, principal, state) do
    state = %{
      state
      | proposals:
          Map.reject(state.proposals, fn {_key, proposal} ->
            LocalAction.handles?(proposal.intent.type) and
              Scene.revalidate(state.scene, proposal) != :ok
          end)
    }

    if valid_intent?(intent, true),
      do: store_proposal(state, principal, id, intent),
      else: {:reply, {:error, :invalid_request}, state}
  end

  defp authorized_call({:cancel, id}, _caller, principal, state) do
    if Scope.id?(id),
      do: {:reply, :ok, retire_local_proposal(state, principal, id)},
      else: {:reply, {:error, :invalid_request}, state}
  end

  defp authorized_call({:submit, request}, _caller, principal, state) do
    if valid_request?(request),
      do: command(state, principal, request.id, {:direct, request.revision, request.intent}),
      else: {:reply, {:error, :invalid_request}, state}
  end

  defp authorized_call({:confirm, id, proposal_id}, _caller, principal, state) do
    if Scope.id?(id) and Scope.id?(proposal_id),
      do: command(state, principal, id, {:confirm, proposal_id}),
      else: {:reply, {:error, :invalid_request}, state}
  end

  defp authorized_call({:step, plan, index, payload}, _caller, principal, state) do
    with true <-
           not is_nil(state.storage) and Scope.id?(plan) and is_integer(index) and index in 0..7,
         true <- valid_step_payload?(payload),
         :ok <- Actions.previous_step(principal, plan, index) do
      command(state, principal, Actions.step_id(plan, index), {:step, plan, index, payload})
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      _ -> {:reply, {:error, :invalid_plan}, state}
    end
  end

  defp authorized_call(_request, _caller, _principal, state),
    do: {:reply, {:error, :invalid_request}, state}

  defp store_proposal(state, principal, id, intent) do
    case Scene.propose(state.scene, principal.actor_id, intent, id) do
      {:ok, proposal} ->
        proposal = bind_local_quote(proposal, principal)
        key = proposal_key(principal, proposal.id)

        case state.proposals[key] do
          nil when map_size(state.proposals) >= 64 ->
            {:reply, {:error, :capacity_limit}, state}

          nil ->
            {:reply, {:ok, Scene.proposal_view(proposal)},
             %{state | proposals: Map.put(state.proposals, key, proposal)}}

          ^proposal ->
            {:reply, {:ok, Scene.proposal_view(proposal)}, state}

          _ ->
            {:reply, {:error, :proposal_id_reused}, state}
        end

      other ->
        {:reply, other, state}
    end
  end

  # Retiring a quote must not let a delayed confirmation authorize new terms.
  # Callers confirm the returned opaque identity, never their proposal request ID.
  defp bind_local_quote(proposal, principal) do
    if LocalAction.handles?(proposal.intent.type) do
      digest =
        :crypto.hash(
          :sha256,
          :erlang.term_to_binary({principal.id, principal.campaign_id, proposal}, [:deterministic])
        )
        |> Base.encode16(case: :lower)

      %{proposal | id: "quote-" <> digest}
    else
      proposal
    end
  end

  defp retire_local_proposal(state, principal, id) do
    key = proposal_key(principal, id)

    case state.proposals[key] do
      %{intent: intent} ->
        if LocalAction.handles?(intent.type),
          do: %{state | proposals: Map.delete(state.proposals, key)},
          else: state

      nil ->
        state
    end
  end

  defp command(%{storage: storage} = state, principal, id, payload) when not is_nil(storage) do
    case Actions.receipt(principal, id, payload) do
      {:ok, receipt} -> {:reply, receipt_reply(state, principal, receipt), state}
      :new -> execute(state, principal, id, payload, {principal.id, id})
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp command(state, principal, id, payload) do
    key = {principal.id, id}

    case state.receipts[key] do
      %{payload: ^payload, actor_id: actor_id, campaign_id: campaign_id} = receipt
      when actor_id == principal.actor_id and campaign_id == principal.campaign_id ->
        {:reply, receipt_reply(state, principal, receipt), state}

      %{} ->
        {:reply, {:error, :request_id_reused}, state}

      nil when map_size(state.receipts) >= state.limit ->
        {:reply, {:error, :capacity_limit}, state}

      nil ->
        execute(state, principal, id, payload, key)
    end
  end

  defp execute(state, %{role: :spectator}, _id, _payload, _key),
    do: {:reply, {:error, :read_only}, state}

  defp execute(state, %{status: :paused}, _id, _payload, _key),
    do: {:reply, {:error, :paused}, state}

  defp execute(state, principal, id, payload, key) do
    with {:ok, proposal} <- resolve_proposal(state, principal, payload),
         :ok <- Scene.revalidate(state.scene, proposal),
         readings <- Clock.read(state.clock),
         draws <- draws(state, proposal),
         inputs <- %{
           scope: state.scene.scope,
           expected_revision: state.scene.revision,
           event_id: event_id(state, principal, id),
           draws: draws,
           recorded_at: readings.utc
         },
         {:ok, next, effects} <- Scene.confirm(state.scene, proposal, inputs),
         receipt = %{
           id: id,
           actor_id: principal.actor_id,
           campaign_id: principal.campaign_id,
           payload: payload,
           effects: effects,
           revision: next.revision
         },
         {:ok, receipt} <- persist(state, principal, next, receipt) do
      Actions.fault(state.storage_opts, :after_commit)
      receipts = if state.storage, do: state.receipts, else: Map.put(state.receipts, key, receipt)

      state =
        %{state | scene: next, receipts: receipts}
        |> retire_local_proposal(principal, confirmed_id(payload))

      Actions.fault(state.storage_opts, :after_install)
      {:reply, receipt_reply(state, principal, receipt), notify(state)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      {:clarify, _field} -> {:reply, {:error, :invalid_request}, state}
    end
  end

  defp confirmed_id({:confirm, id}), do: id
  defp confirmed_id({:step, _plan, _index, payload}), do: confirmed_id(payload)
  defp confirmed_id(_payload), do: nil

  defp persist(%{storage: nil}, _principal, _next, receipt), do: {:ok, receipt}

  defp persist(state, principal, next, receipt),
    do: Actions.commit(principal, state.scene, next, receipt, state.storage_opts)

  defp refresh(%{storage: nil} = state), do: {:ok, state}

  defp refresh(state) do
    with %Snapshot{} = snapshot <- Repo.get(Snapshot, state.storage.snapshot_id),
         {:ok, scene} <- Snapshots.load(snapshot) do
      {:ok, %{state | scene: scene}}
    else
      _ -> {:error, :recovery_failed}
    end
  end

  defp resolve_proposal(state, principal, {:direct, revision, intent}) do
    cond do
      revision != state.scene.revision ->
        {:error, :stale_revision}

      not match?(%{"kind" => "take"}, state.scene.actions[intent.type]) ->
        {:error, :confirmation_required}

      true ->
        Scene.propose(state.scene, principal.actor_id, intent, "direct")
    end
  end

  defp resolve_proposal(state, principal, {:step, _plan, _index, payload}),
    do: resolve_proposal(state, principal, payload)

  defp resolve_proposal(state, principal, {:confirm, id}) do
    case state.proposals[proposal_key(principal, id)] do
      %{actor_id: actor_id} = proposal when actor_id == principal.actor_id -> {:ok, proposal}
      _ -> {:error, :unavailable}
    end
  end

  defp draws(state, proposal) do
    case proposal.terms do
      %{"kind" => "check", "check" => check} -> state.draw.(check)
      _ -> []
    end
  end

  defp receipt_reply(state, principal, receipt) do
    {:ok, view} = projection(state, principal)

    {:ok,
     %{
       id: receipt.id,
       revision: receipt.revision,
       effects: Scene.effects_for(receipt.effects, principal),
       view: view,
       durability: if(state.storage, do: :durable, else: :ephemeral)
     }}
  end

  defp event_id(state, principal, id),
    do:
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({Scope.key(state.scene.scope), principal.id, id})
      )
      |> Base.encode16(case: :lower)

  defp proposal_key(principal, id),
    do: {principal.id, principal.campaign_id, principal.actor_id, id}

  defp valid_request?(%{id: id, revision: revision, intent: intent} = request),
    do:
      map_size(request) == 3 and
        Scope.id?(id) and is_integer(revision) and revision >= 0 and valid_intent?(intent, false)

  defp valid_request?(_request), do: false

  defp valid_step_payload?({:confirm, id}), do: Scope.id?(id)

  defp valid_step_payload?({:direct, revision, intent}),
    do: valid_request?(%{id: "step", revision: revision, intent: intent})

  defp valid_step_payload?(_payload), do: false

  defp valid_intent?(%{type: type, target_id: target} = intent, _clarification),
    do:
      LocalAction.valid_intent?(intent) or
        (map_size(intent) == 2 and Scope.id?(type) and Scope.id?(target))

  defp valid_intent?(%{type: type} = intent, true), do: map_size(intent) == 1 and Scope.id?(type)
  defp valid_intent?(_intent, _clarification), do: false

  defp projection(state, principal) do
    with {:ok, view} <- State.view(state.scene, principal) do
      {:ok,
       Map.put(
         view,
         :disconnected,
         Enum.filter(MapSet.to_list(state.disconnected), fn id ->
           Enum.any?(view.actors, &(&1.id == id))
         end)
         |> Enum.sort()
       )}
    end
  end

  defp sync_status(%{scene: %{status: status}} = state, status), do: state
  defp sync_status(state, :paused), do: %{state | scene: State.pause(state.scene)}
  defp sync_status(state, :active), do: %{state | scene: State.resume(state.scene)}

  defp unbind(state, pid) do
    case Map.pop(state.bindings, pid) do
      {nil, _bindings} ->
        state

      {binding, bindings} ->
        Process.demonitor(binding.monitor, [:flush])

        disconnected =
          if Enum.any?(bindings, fn {_pid, other} -> other.actor_id == binding.actor_id end),
            do: state.disconnected,
            else: MapSet.put(state.disconnected, binding.actor_id)

        %{state | bindings: bindings, disconnected: disconnected}
    end
  end

  defp notify(state) do
    bindings =
      Map.new(state.bindings, fn {pid, binding} ->
        unless binding.pending, do: send(pid, {:zone_changed, self()})
        {pid, %{binding | pending: true}}
      end)

    %{state | bindings: bindings}
  end
end
