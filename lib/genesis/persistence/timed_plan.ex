defmodule Genesis.Persistence.TimedPlan do
  @moduledoc "Revalidates a durable ready proposal for the existing atomic publication coordinator."
  alias Genesis.Core.RecordedChange
  alias Genesis.Persistence.{Codec, GlobalPublication, PreparationInputs, Preparations, Window}
  alias Genesis.{Repo, Worlds}

  @spec prepare(scope :: term(), world :: map(), id :: String.t()) :: term()
  def prepare(scope, world, id) do
    with {:ok, %{status: "ready"} = row} <- Preparations.authorized(scope, world.id, id),
         %{status: "sealed"} = window <- Repo.get(Window, row.window_id),
         {:ok, inputs} <- PreparationInputs.validate(scope, world, window, row.input),
         true <- inputs.manifest == row.manifest,
         {:ok, %{"status" => "ready"} = work} <- Codec.load(row.work),
         true <- Codec.digest(work) == row.digest,
         true <- work["target"] == row.manifest["target"] and work["calendar"] == world.calendar,
         mapping = Map.new(inputs.sources, &{&1.core_event_id, mapped_id(&1)}),
         {:ok, zones} <- zones(inputs, work, mapping),
         :ok <- conservation(zones),
         {:ok, global} <- globals(world, inputs.entries, mapping) do
      manifest =
        row.manifest
        |> Map.put("preparation_id", row.id)
        |> Map.put("preparation_digest", row.digest)
        |> Map.put(
          "zones",
          Enum.map(
            zones,
            &%{
              "zone_id" => &1.published.zone_id,
              "published_snapshot_id" => &1.published_snapshot.id,
              "base_digest" => &1.published_snapshot.digest,
              "candidate_digest" => Codec.digest(&1.candidate)
            }
          )
        )
        |> Map.put("global", Enum.map(global, & &1.manifest))

      {:ok,
       %{
         id: Codec.digest(manifest),
         manifest: manifest,
         preparation: row,
         zones: zones,
         experience: %{id: nil, zone_id: hd(zones).published.zone_id},
         entries: inputs.entries,
         sources: inputs.sources,
         mapping: mapping,
         generated: work["generated"],
         global: global
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :stale_preparation}
    end
  end

  defp mapped_id(source) do
    {:ok, effect} = Codec.load(source.event)

    if Map.has_key?(effect, :schedule_id),
      do: source.core_event_id,
      else: Worlds.named_id(["incorporation", source.experience_id, source.id])
  end

  defp zones(inputs, work, mapping) do
    Enum.reduce_while(inputs.rows, {:ok, []}, fn row, {:ok, acc} ->
      original = inputs.states[row.zone_id]

      case RecordedChange.publish(work["states"][row.zone_id], original, work["target"], mapping) do
        {:ok, candidate} ->
          {:cont,
           {:ok, acc ++ [%{published_snapshot: row, published: original, candidate: candidate}]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp conservation(zones) do
    original = identities(zones, :published)
    current = identities(zones, :candidate)

    if length(current) == MapSet.size(MapSet.new(current)) and
         MapSet.subset?(MapSet.new(original), MapSet.new(current)),
       do: :ok,
       else: {:error, :identity_conflict}
  end

  defp identities(zones, key),
    do:
      for(
        zone <- zones,
        field <- [:actors, :items, :knowledge],
        id <- Map.keys(Map.fetch!(Map.fetch!(zone, key), field)),
        do: {field, id}
      )

  defp globals(world, entries, mapping) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case GlobalPublication.prepare(world, entry.experience, mapping) do
        {:ok, plans} ->
          {:cont, {:ok, if(entry.decision["mode"] == "include", do: acc ++ plans, else: acc)}}

        error ->
          {:halt, error}
      end
    end)
  end
end
