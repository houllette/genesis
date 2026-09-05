defmodule Genesis.Persistence.IncorporationPlan do
  @moduledoc "Replay-checked one-Experience, eight-zone publication plans. No clocks, rerolls or live process calls."
  import Ecto.Query
  alias Genesis.Core.Incorporation, as: Projection
  alias Genesis.Experiences
  alias Genesis.Persistence.Access
  alias Genesis.Persistence.Checkpoint
  alias Genesis.Persistence.Claim
  alias Genesis.Persistence.Codec
  alias Genesis.Persistence.Event
  alias Genesis.Persistence.Experience
  alias Genesis.Persistence.Footprints
  alias Genesis.Persistence.GlobalPublication
  alias Genesis.Persistence.Replay
  alias Genesis.Persistence.Seals
  alias Genesis.Persistence.Snapshots
  alias Genesis.Persistence.Window
  alias Genesis.Repo
  alias Genesis.Worlds

  @spec prepare(
          scope :: term(),
          world :: map(),
          experience :: String.t(),
          operation :: String.t() | nil
        ) :: term()
  def prepare(scope, world, id, operation \\ nil) do
    with :ok <- Access.world(scope, world.id, ["steward"]),
         {:ok, %{status: "ready"} = exp} <- Experiences.get(scope, world.id, id, ["gm"]),
         %Window{status: "open"} = window <- Repo.get(Window, exp.window_id),
         true <- window.base_revision == world.revision and window.generation == world.generation,
         true <-
           Repo.aggregate(from(e in Experience, where: e.window_id == ^window.id), :count) == 1,
         :ok <- Seals.validate(exp),
         :ok <- zero_completion(exp),
         {:ok, rows} <- Footprints.snapshots(exp),
         {:ok, zones} <- load_zones(scope, world, rows, operation),
         :ok <- claims_match(world, exp, zones),
         :ok <- Snapshots.check_index(Enum.map(zones, & &1.published)),
         sources =
           Repo.all(
             from e in Event,
               where: e.experience_id == ^exp.id and not is_nil(e.actor_id),
               order_by: e.cursor,
               limit: 201
           ),
         true <- length(sources) <= 200,
         true <-
           Enum.all?(
             sources,
             &(&1.kind == "experience" and &1.snapshot_id in Enum.map(rows, fn r -> r.id end))
           ),
         mapping =
           Map.new(
             sources,
             &{&1.core_event_id, Worlds.named_id(["incorporation", exp.id, &1.id])}
           ),
         true <- map_size(mapping) == length(sources),
         {:ok, candidates} <- Projection.project_many(zones, mapping),
         {:ok, global} <- GlobalPublication.prepare(world, exp, mapping) do
      zones = Enum.zip_with(zones, candidates, &Map.put(&1, :candidate, &2))

      manifest = %{
        "world_id" => world.id,
        "generation" => world.generation,
        "world_revision" => world.revision,
        "experience_id" => exp.id,
        "completion_digest" => Codec.digest(exp.completion),
        "zones" => Enum.map(zones, &zone_manifest/1),
        "sources" => Enum.map(sources, & &1.id),
        "target" => world.fictional_time
      }

      manifest =
        if global == [],
          do: manifest,
          else: Map.put(manifest, "global", Enum.map(global, & &1.manifest))

      {:ok,
       %{
         manifest: manifest,
         id: Codec.digest(manifest),
         experience: exp,
         zones: zones,
         sources: sources,
         mapping: mapping,
         global: global
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :incorporation_not_ready}
    end
  end

  defp load_zones(scope, world, rows, operation) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case load_zone(scope, world, row, operation) do
        {:ok, zone} -> {:cont, {:ok, acc ++ [zone]}}
        error -> {:halt, error}
      end
    end)
  end

  defp load_zone(scope, world, row, operation) do
    with {:ok, working} <- Snapshots.load(row),
         :ok <- zero_duration(working),
         {:ok, published_row, published} <- Footprints.base(row),
         {:ok, ^published} <- Snapshots.load(published_row),
         %Checkpoint{} = cp <-
           Repo.one(
             from c in Checkpoint, where: c.snapshot_id == ^row.id, order_by: c.cursor, limit: 1
           ),
         {:ok, base} <- Codec.load_state(cp.state),
         {:ok, ^working} <- Replay.restore(scope, world.id, cp.id, operation) do
      {:ok,
       %{
         published: published,
         published_snapshot: published_row,
         working: working,
         working_snapshot: row,
         working_base: base,
         working_checkpoint: cp
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :corrupt_history}
    end
  end

  defp zone_manifest(zone),
    do: %{
      "zone_id" => zone.published.zone_id,
      "published_snapshot_id" => zone.published_snapshot.id,
      "working_snapshot_id" => zone.working_snapshot.id,
      "working_digest" => zone.working_snapshot.digest,
      "base_digest" => zone.published_snapshot.digest,
      "base_checkpoint_id" => zone.working_snapshot.base_checkpoint_id,
      "working_checkpoint_id" => zone.working_checkpoint.id,
      "candidate_digest" => Codec.digest(zone.candidate)
    }

  defp zero_duration(%{elapsed: 0}), do: :ok
  defp zero_duration(_), do: {:error, :time_reconciliation_unavailable}

  defp zero_completion(%{completion: %{"elapsed_seconds" => 0}}), do: :ok
  defp zero_completion(_), do: {:error, :time_reconciliation_unavailable}

  defp claims_match(world, exp, zones) do
    expected = Enum.flat_map(zones, &Footprints.resources(&1.published))

    actual =
      Repo.all(
        from c in Claim,
          where:
            c.world_id == ^world.id and c.generation == ^world.generation and
              c.experience_id == ^exp.id,
          select: {c.resource_kind, c.resource_id}
      )

    if Enum.sort(expected) == Enum.sort(actual), do: :ok, else: {:error, :stale_claims}
  end
end
