defmodule Genesis.Persistence.PreparationInputs do
  @moduledoc "Bounded admission and immutable replay inputs for one whole advancement window."
  import Ecto.Query
  alias Genesis.Core.LocalTime, as: TimeRules

  alias Genesis.Persistence.{
    Access,
    Checkpoint,
    Claim,
    Codec,
    Event,
    Experience,
    Footprints,
    LocalTime,
    Seals,
    Snapshots,
    Transition
  }

  alias Genesis.Repo

  @spec validate(scope :: term(), world :: map(), window :: map(), attrs :: map()) :: term()
  def validate(scope, world, window, attrs) do
    with :ok <- Access.world(scope, world.id, ["steward"]),
         true <- valid_attrs?(attrs),
         true <- window.generation == world.generation and window.base_revision == world.revision,
         exps =
           Repo.all(
             from e in Experience, where: e.window_id == ^window.id, order_by: e.id, limit: 17
           ),
         true <-
           length(exps) <= 16 and
             Enum.sort(Map.keys(attrs["decisions"])) == Enum.map(exps, & &1.id),
         {:ok, entries} <- experiences(scope, world, exps, attrs["decisions"]),
         rows = Snapshots.published(world),
         true <- length(rows) in 1..8,
         {:ok, states} <- Footprints.load(rows),
         true <- Enum.all?(states, fn {_, s} -> s.time.value == world.fictional_time end),
         :ok <- Snapshots.check_index(Enum.map(states, &elem(&1, 1))),
         {:ok, sources, records} <- records(entries),
         true <- length(sources) <= 512,
         :ok <- exclusions(entries, sources),
         target = target(world, entries, attrs["downtime_seconds"]),
         true <- target - world.fictional_time <= 31_622_400 do
      included = Enum.filter(entries, &(&1.decision["mode"] == "include"))
      ids = Enum.map(included, & &1.experience.id)

      manifest = %{
        "format" => 8,
        "world_id" => world.id,
        "generation" => world.generation,
        "world_revision" => world.revision,
        "window_id" => window.id,
        "target" => target,
        "calendar" => world.calendar,
        "policy" => "timeline-v1-due-first-commit-ties",
        "experiences" =>
          Enum.map(entries, fn entry ->
            %{
              "id" => entry.experience.id,
              "seal" => Codec.digest(entry.experience.completion),
              "start_offset" => entry.experience.start_offset,
              "decision" => entry.decision
            }
          end),
        "zones" =>
          Enum.map(states, fn {row, _} ->
            %{
              "zone_id" => row.zone_id,
              "published_snapshot_id" => row.id,
              "base_digest" => row.digest
            }
          end),
        "sources" => Enum.map(sources, & &1.id)
      }

      {:ok,
       %{
         manifest: manifest,
         states: Map.new(states, fn {_, s} -> {s.zone_id, s} end),
         rows: rows,
         entries: entries,
         sources: Enum.filter(sources, &(&1.experience_id in ids)),
         records: Enum.filter(records, &(&1["experience_id"] in ids))
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :window_not_ready}
    end
  end

  @spec valid_attrs?(attrs :: term()) :: boolean()
  def valid_attrs?(attrs) when is_map(attrs),
    do:
      Enum.sort(Map.keys(attrs)) == ~w(decisions downtime_seconds reason) and
        is_map(attrs["decisions"]) and map_size(attrs["decisions"]) <= 16 and
        TimeRules.reason?(attrs["reason"]) and is_integer(attrs["downtime_seconds"]) and
        attrs["downtime_seconds"] in 0..31_622_400

  def valid_attrs?(_attrs), do: false

  defp experiences(scope, world, exps, decisions) do
    Enum.reduce_while(exps, {:ok, []}, fn exp, {:ok, acc} ->
      with {:ok, _} <- Genesis.Experiences.get(scope, world.id, exp.id, ["gm"]),
           true <- exp.status in ["ready", "needs_review"],
           :ok <- Seals.validate(exp),
           {:ok, summary} <- LocalTime.summary(exp),
           {:ok, rows} <- Footprints.snapshots(exp),
           :ok <- claims(world, exp, rows),
           {:ok, decision} <- decision(decisions[exp.id], exp, summary) do
        {:cont, {:ok, acc ++ [%{experience: exp, rows: rows, decision: decision}]}}
      else
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, :unsealed_experience}}
      end
    end)
  end

  defp decision(%{"mode" => mode, "reason" => reason} = attrs, exp, summary)
       when mode in ["include", "exclude"] do
    total = Map.get(attrs, "elapsed_seconds", exp.completion["elapsed_seconds"])

    if Map.keys(attrs) -- ~w(mode reason elapsed_seconds) == [] and TimeRules.reason?(reason) and
         is_integer(total) and total in 0..31_622_400 and total >= summary.elapsed_seconds,
       do: {:ok, Map.put(attrs, "elapsed_seconds", total)},
       else: {:error, :invalid_time_decision}
  end

  defp decision(_attrs, _exp, _summary), do: {:error, :invalid_time_decision}

  defp target(world, entries, downtime) do
    ends =
      for entry <- entries,
          entry.decision["mode"] == "include",
          do: entry.experience.start_offset + entry.decision["elapsed_seconds"]

    world.fictional_time + Enum.max(ends, fn -> 0 end) + downtime
  end

  defp claims(world, exp, rows) do
    bases = Enum.map(rows, &Footprints.base/1)

    if Enum.all?(bases, &match?({:ok, _, _}, &1)) do
      expected =
        Enum.flat_map(bases, fn {:ok, _, base} -> Footprints.resources(base) end) |> Enum.sort()

      actual =
        Repo.all(
          from c in Claim,
            where:
              c.world_id == ^world.id and c.generation == ^world.generation and
                c.experience_id == ^exp.id,
            select: {c.resource_kind, c.resource_id}
        )
        |> Enum.sort()

      if actual == expected, do: :ok, else: {:error, :stale_claims}
    else
      {:error, :invalid_checkpoint}
    end
  end

  defp records(entries) do
    Enum.reduce_while(entries, {:ok, [], []}, fn entry, {:ok, sources, records} ->
      case experience_records(entry) do
        {:ok, rows, nodes} -> {:cont, {:ok, sources ++ rows, records ++ nodes}}
        error -> {:halt, error}
      end
    end)
  end

  defp experience_records(entry) do
    Enum.reduce_while(entry.rows, {:ok, [], []}, fn snapshot, {:ok, sources, records} ->
      with %Checkpoint{} = cp <-
             Repo.one(
               from c in Checkpoint,
                 where: c.snapshot_id == ^snapshot.id,
                 order_by: c.cursor,
                 limit: 1
             ),
           {:ok, base} <- Codec.load_state(cp.state),
           true <- cp.digest == Codec.digest(base),
           events =
             Repo.all(
               from e in Event,
                 where: e.snapshot_id == ^snapshot.id and e.cursor > ^cp.cursor,
                 order_by: e.cursor,
                 limit: 513
             ),
           true <- length(events) <= 512,
           {:ok, state, nodes} <- replay(base, events),
           true <- Codec.digest(state) == snapshot.digest do
        selected = Enum.filter(events, &(&1.transition != %{}))
        {:cont, {:ok, sources ++ selected, records ++ nodes}}
      else
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, :corrupt_history}}
      end
    end)
  end

  defp replay(base, events) do
    Enum.reduce_while(events, {:ok, base, []}, &replay_row/2)
  end

  defp replay_row(%{transition: transition, actor_id: nil}, acc) when map_size(transition) == 0,
    do: {:cont, acc}

  defp replay_row(row, {:ok, before, acc}) do
    with {:ok, next} <- Transition.apply(before, row.transition),
         {:ok, effect} <- Codec.load(row.event) do
      at = Map.get(effect, :occurred_at, next.time.value)

      node = %{
        "zone" => before.zone_id,
        "before" => before,
        "after" => next,
        "effect" => effect,
        "at" => at,
        "cursor" => row.cursor,
        "source_id" => row.id,
        "experience_id" => row.experience_id
      }

      {:cont, {:ok, next, acc ++ [node]}}
    else
      _ -> {:halt, {:error, :corrupt_history}}
    end
  end

  defp exclusions(entries, sources) do
    excluded = for entry <- entries, entry.decision["mode"] == "exclude", do: entry.experience.id

    forbidden =
      sources |> Enum.filter(&(&1.experience_id in excluded)) |> MapSet.new(& &1.core_event_id)

    conflict =
      Enum.any?(sources, fn row ->
        {:ok, effect} = Codec.load(row.event)

        row.experience_id not in excluded and
          Enum.any?(Map.get(effect, :source_ids, []), &MapSet.member?(forbidden, &1))
      end)

    if conflict, do: {:error, :excluded_dependency}, else: :ok
  end
end
