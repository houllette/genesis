defmodule Genesis.Engine.DurableWorld do
  @moduledoc "Persistent orchestration in the existing World owner, not a second process."
  alias Genesis.Core.Scope
  alias Genesis.Engine.{Session, Supervisor, Zone}
  alias Genesis.Experiences

  alias Genesis.Persistence.{
    Access,
    Actions,
    Authority,
    Curation,
    Incorporation,
    Snapshot,
    Snapshots
  }

  alias Genesis.Repo

  @spec call(state :: map(), scope :: term(), command :: term(), caller :: pid()) ::
          {:reply, term(), map()}
  def call(state, scope, {:create_zone, attrs, request}, _caller),
    do: {:reply, Curation.create_zone(scope, state.world_id, attrs, request), state}

  def call(state, scope, {:curate, zone_id, operation}, _caller) do
    published =
      struct(Scope, world_id: state.world_id, generation: state.generation, kind: :published)

    with :ok <- Access.world(scope, state.world_id, ["steward", "builder"]),
         true <- Scope.id?(zone_id),
         %Snapshot{} = snapshot <- Snapshots.find(state.world_id, published, zone_id),
         {:ok, zone, state} <- zone(state, snapshot) do
      {:reply, GenServer.call(zone, {:curate, scope, operation}, 10_000), state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      _ -> {:reply, {:error, :unavailable}, state}
    end
  end

  def call(state, scope, {:open, experience, actor, consumer}, consumer) do
    with {:ok, principal, snapshot} <-
           Authority.principal(scope, state.world_id, experience, actor),
         {:ok, zone, state} <- zone(state, snapshot),
         true <- map_size(state.grants) < 256 do
      token = make_ref()

      result =
        DynamicSupervisor.start_child(
          state.workers,
          {Session, world: self(), zone: zone, token: token, consumer: consumer}
        )

      remember_session(result, state, token, principal)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      _ -> {:reply, {:error, :capacity_limit}, state}
    end
  end

  def call(state, scope, {:status, experience, action, revision, request}, _caller) do
    with {:ok, _exp} <- Experiences.get(scope, state.world_id, experience, ["gm"]),
         %Snapshot{} = snapshot <-
           Repo.get_by(Snapshot, world_id: state.world_id, experience_id: experience),
         {:ok, zone, state} <- zone(state, snapshot) do
      reply = GenServer.call(zone, {:control, scope, action, revision, request}, 10_000)
      {:reply, reply, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      _ -> {:reply, {:error, :unavailable}, state}
    end
  end

  def call(state, scope, {:preview_incorporation, experience}, _caller) do
    with {:ok, user} <- Access.user_id(scope),
         true <- map_size(state.previews) < 8,
         {:ok, prepared} <- Incorporation.prepare(scope, state.world_id, experience) do
      reply = %{
        id: prepared.id,
        elapsed_seconds: 0,
        source_events: length(prepared.sources),
        zone_id: prepared.candidate.zone_id
      }

      {:reply, {:ok, reply},
       %{state | previews: Map.put(state.previews, {user, prepared.id}, prepared)}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      _ -> {:reply, {:error, :capacity_limit}, state}
    end
  end

  def call(state, scope, {:incorporate, preview, request}, _caller) do
    case Incorporation.receipt(scope, state.world_id, preview, request) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      :new -> publish(state, scope, preview, request)
      error -> {:reply, error, state}
    end
  end

  def call(state, _scope, _command, _caller),
    do: {:reply, {:error, :unsupported_operation}, state}

  defp remember_session({:ok, pid} = result, state, token, principal),
    do:
      {:reply, result,
       %{
         state
         | grants: Map.put(state.grants, token, principal),
           sessions: Map.put(state.sessions, Process.monitor(pid), token)
       }}

  defp remember_session(error, state, _token, _principal), do: {:reply, error, state}

  defp publish(state, scope, preview, request) do
    with {:ok, user} <- Access.user_id(scope),
         %{} = prepared <- state.previews[{user, preview}],
         {:ok, zone, state} <- zone(state, prepared.published_snapshot),
         {:ok, result} <-
           Incorporation.publish(scope, state.world_id, prepared, request, state.zone_opts) do
      Actions.fault(state.zone_opts, :after_commit)
      :ok = GenServer.call(zone, :install_committed)
      Actions.fault(state.zone_opts, :after_install)
      {:reply, {:ok, result}, %{state | previews: Map.delete(state.previews, {user, preview})}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      _ -> {:reply, {:error, :stale_preview}, state}
    end
  end

  @spec zone(state :: map(), snapshot :: map()) :: {:ok, pid(), map()} | {:error, term()}
  def zone(state, snapshot) do
    with {:ok, scene} <- Snapshots.load(snapshot) do
      key = {Scope.key(scene.scope), scene.zone_id}
      name = Supervisor.via(state.registry, {:zone, key})

      case GenServer.whereis(name) do
        nil -> start_zone(state, snapshot, scene, key, name)
        pid -> {:ok, pid, state}
      end
    end
  end

  defp start_zone(state, snapshot, scene, key, name) do
    opts =
      Keyword.merge(state.zone_opts,
        world: self(),
        scene: scene,
        name: name,
        storage: %{snapshot_id: snapshot.id}
      )

    case DynamicSupervisor.start_child(state.workers, {Zone, opts}) do
      {:ok, pid} ->
        entry = %{pid: pid, monitor: Process.monitor(pid), actors: Map.keys(scene.actors)}
        {:ok, pid, %{state | zones: Map.put(state.zones, key, entry)}}

      error ->
        error
    end
  end
end
