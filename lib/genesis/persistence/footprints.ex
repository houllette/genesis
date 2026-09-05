defmodule Genesis.Persistence.Footprints do
  @moduledoc "Bounded Experience zones and immutable base references. Expansion acquires durable claims before any short transfer reservation."
  import Ecto.Query
  alias Genesis.Core.{Scope, State}
  alias Genesis.Experiences
  alias Genesis.Persistence.{Checkpoint, Claim, Codec, Snapshot, Snapshots, Tx, Window, World}
  alias Genesis.Repo

  @spec snapshots(experience :: map()) :: {:ok, list()} | {:error, atom()}
  def snapshots(exp) do
    rows =
      Repo.all(
        from s in Snapshot,
          where: s.world_id == ^exp.world_id and s.experience_id == ^exp.id,
          order_by: s.zone_id,
          limit: 9
      )

    if length(rows) in 1..8, do: {:ok, rows}, else: {:error, :footprint_limit}
  end

  @spec actor_snapshot(experience :: map(), actor :: String.t() | nil) ::
          {:ok, map()} | {:error, atom()}
  def actor_snapshot(exp, nil) do
    case Repo.get_by(Snapshot,
           world_id: exp.world_id,
           experience_id: exp.id,
           zone_id: exp.zone_id
         ) do
      nil -> {:error, :unavailable}
      row -> {:ok, row}
    end
  end

  def actor_snapshot(exp, actor) do
    with {:ok, rows} <- snapshots(exp), {:ok, loaded} <- load(rows) do
      locate_actor(loaded, actor)
    end
  end

  defp locate_actor(loaded, actor) do
    case Enum.filter(loaded, fn {_row, state} -> Map.has_key?(state.actors, actor) end) do
      [{row, _state}] -> {:ok, row}
      _ -> {:error, :unavailable}
    end
  end

  @spec load(rows :: list()) :: {:ok, list()} | {:error, atom()}
  def load(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, loaded} ->
      case Snapshots.load(row) do
        {:ok, state} -> {:cont, {:ok, loaded ++ [{row, state}]}}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Returns an existing working destination or a read-only candidate from the current immutable base. Does not claim it."
  @spec destination(world :: map(), exp :: map(), source :: State.t(), zone :: String.t()) ::
          term()
  def destination(world, exp, source, zone) do
    with true <- Scope.id?(zone),
         %Window{status: "open"} = window <- Repo.get(Window, exp.window_id),
         true <- window.generation == world.generation and window.base_revision == world.revision do
      case Snapshots.find(world.id, source.scope, zone) do
        nil -> published_destination(world, source, zone)
        row -> working_destination(row)
      end
    else
      _ -> {:error, :stale_window}
    end
  end

  defp working_destination(row) do
    with {:ok, scene} <- Snapshots.load(row), do: {:ok, row, scene}
  end

  defp published_destination(world, source, zone) do
    published = %{source.scope | kind: :published, window_id: nil, id: nil}

    with %Snapshot{} = row <- Snapshots.find(world.id, published, zone),
         {:ok, base} <- Snapshots.load(row),
         :ok <- available(world, base) do
      scene = Experiences.rescope(base, source.scope)
      {:ok, nil, %{scene | revision: 0, elapsed: 0, events: [], status: :active}}
    else
      nil -> {:error, :unavailable}
      error -> error
    end
  end

  @doc "Called inside the World transaction after pure travel validation. Claims survive aborted travel and pause."
  @spec expand!(world :: map(), exp :: map(), scene :: State.t(), principal :: map()) :: term()
  def expand!(world, exp, scene, principal) do
    with {:ok, rows} <- snapshots(exp),
         true <- length(rows) < 8,
         {:ok, states} <- load(rows),
         true <- Enum.all?(states, fn {_row, state} -> state.elapsed == 0 end),
         published_scope = %{scene.scope | kind: :published, window_id: nil, id: nil},
         %Snapshot{} = base_row <- Snapshots.find(world.id, published_scope, scene.zone_id),
         {:ok, base} <- Snapshots.load(base_row),
         :ok <- available(world, base) do
      checkpoint = Snapshots.checkpoint!(base_row, world.cursor)
      row = Snapshots.create!(world, scene, exp.id, checkpoint.id)
      claim!(world, base, exp.id)
      Tx.update!(exp, %{revision: exp.revision + 1})

      event =
        Tx.event!(world, %{
          snapshot_id: row.id,
          scope_key: row.scope_key,
          kind: "experience",
          experience_id: exp.id,
          campaign_id: exp.campaign_id,
          principal_id: principal.user_id,
          audience_users: [principal.user_id],
          event: Codec.dump!(%{type: "footprint_extended", result: %{"zone_id" => scene.zone_id}})
        })

      Snapshots.checkpoint!(row, event.cursor)
      {:ok, row}
    else
      false -> {:error, :footprint_expansion_unavailable}
      error -> error
    end
  end

  @spec resources(state :: State.t()) :: list()
  def resources(state),
    do:
      [{"zone", state.zone_id}] ++
        Enum.map(Map.keys(state.actors), &{"actor", &1}) ++
        Enum.map(Map.keys(state.items), &{"item", &1})

  @spec available(world :: World.t(), state :: State.t()) :: :ok | {:error, atom()}
  def available(world, state) do
    claimed =
      Enum.any?(resources(state), fn {kind, id} ->
        Repo.exists?(
          from c in Claim,
            where:
              c.world_id == ^world.id and c.generation == ^world.generation and
                c.resource_kind == ^kind and c.resource_id == ^id
        )
      end)

    if claimed, do: {:error, :claimed}, else: :ok
  end

  @spec claim!(world :: World.t(), state :: State.t(), experience :: String.t()) :: :ok
  def claim!(world, state, experience),
    do:
      Enum.each(resources(state), fn {kind, id} ->
        Tx.insert!(Claim, %{
          world_id: world.id,
          generation: world.generation,
          resource_kind: kind,
          resource_id: id,
          experience_id: experience
        })
      end)

  @spec base(snapshot :: map()) :: {:ok, map(), State.t()} | {:error, atom()}
  def base(%{base_checkpoint_id: nil}), do: {:error, :invalid_checkpoint}

  def base(row) do
    with %Checkpoint{} = cp <- Repo.get(Checkpoint, row.base_checkpoint_id),
         %Snapshot{} = published <- Repo.get(Snapshot, cp.snapshot_id),
         {:ok, state} <- Codec.load_state(cp.state),
         true <- cp.digest == Codec.digest(state) and published.digest == cp.digest,
         true <-
           state.scope.kind == :published and state.zone_id == row.zone_id and
             state.scope.world_id == row.world_id and state.scope.generation == row.generation do
      {:ok, published, state}
    else
      _ -> {:error, :invalid_checkpoint}
    end
  end
end
