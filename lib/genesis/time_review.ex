defmodule Genesis.TimeReview do
  @moduledoc "Current-authority, GM-only window and candidate projections. Never exports raw preparation records."
  import Ecto.Query
  alias Genesis.Content.Comparison
  alias Genesis.Core.State

  alias Genesis.Persistence.{
    Access,
    Codec,
    Experience,
    Footprints,
    Preparation,
    Preparations,
    Snapshots,
    Tx,
    Window
  }

  alias Genesis.Repo

  @spec view(scope :: term(), world :: String.t()) :: term()
  def view(scope, id) do
    Tx.run(id, fn world ->
      with :ok <- Access.world(scope, id, ["steward"]),
           window = Repo.one(from w in Window, where: w.world_id == ^id and w.status != "closed"),
           exps = experiences(window),
           true <-
             Enum.all?(exps, &match?({:ok, _}, Genesis.Experiences.get(scope, id, &1.id, ["gm"]))),
           {:ok, pairs} <- Footprints.load(Snapshots.published(world)),
           {:ok, candidate} <- candidate(scope, world, window, pairs) do
        {:ok,
         %{
           world: world,
           window: window,
           experiences: exps,
           candidate: candidate,
           places:
             Enum.map(pairs, fn {row, state} ->
               %{
                 id: row.zone_id,
                 name: state.name,
                 revision: row.revision,
                 actors: Enum.filter(Map.values(state.actors), &(&1.kind == :npc)),
                 schedules: (state.timeline || %{})["schedules"] || %{}
               }
             end)
         }}
      else
        {:error, _} = error -> error
        _ -> {:error, :unavailable}
      end
    end)
  end

  defp experiences(nil), do: []

  defp experiences(window),
    do:
      Repo.all(from e in Experience, where: e.window_id == ^window.id, order_by: e.id, limit: 17)

  defp candidate(_scope, _world, nil, _pairs), do: {:ok, nil}

  defp candidate(scope, world, window, pairs) do
    case Repo.one(
           from p in Preparation,
             where:
               p.window_id == ^window.id and p.status in ["preparing", "ready", "needs_review"]
         ) do
      nil ->
        {:ok, nil}

      row ->
        with {:ok, _} <- Preparations.authorized(scope, world.id, row.id),
             {:ok, work} <- Codec.load(row.work),
             true <- row.digest == Codec.digest(work) do
          places = Enum.map(pairs, &impact(&1, work))

          {:ok,
           %{
             id: row.id,
             status: row.status,
             digest: row.digest,
             target: row.manifest["target"],
             processed: work["processed"],
             places: places,
             conflicts:
               Enum.with_index(work["conflicts"], fn conflict, index ->
                 Map.put(conflict, "id", index)
               end)
           }}
        else
          _ -> {:error, :stale_preparation}
        end
    end
  end

  defp impact({_, before}, work) do
    next = work["states"][before.zone_id]
    {:ok, a} = State.view(before, %{role: :gm, actor_id: nil})
    {:ok, b} = State.view(next, %{role: :gm, actor_id: nil})

    %{
      id: before.zone_id,
      name: before.name,
      changes: Comparison.changes(a, b),
      condition_before: (before.timeline || %{})["condition"] || "normal",
      condition_after: (next.timeline || %{})["condition"] || "normal"
    }
  end
end
