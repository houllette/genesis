defmodule Genesis.Core.Timeline do
  @moduledoc "Resumable deterministic timeline: due points first, then recorded commit order, without rerolls."
  alias Genesis.Core.{DueWork, RecordedChange, Scope}

  @spec new(
          states :: map(),
          records :: [map()],
          target :: integer(),
          calendar :: map(),
          id :: String.t()
        ) :: term()
  def new(states, records, target, calendar, id) do
    if map_size(states) in 1..8 and length(records) <= 512 and is_integer(target) and
         Enum.all?(states, fn {_, state} ->
           target >= state.time.value and target - state.time.value <= 31_622_400
         end) do
      [{_, first} | _] = Enum.to_list(states)

      scope =
        struct(Scope,
          world_id: first.scope.world_id,
          generation: first.scope.generation,
          kind: :candidate,
          window_id: id,
          id: id
        )

      {:ok,
       %{
         "version" => 1,
         "states" =>
           Map.new(states, fn {zone, state} -> {zone, RecordedChange.rescope(state, scope)} end),
         "records" => Enum.sort_by(records, &{&1["at"], &1["cursor"]}),
         "index" => 0,
         "target" => target,
         "calendar" => calendar,
         "generated" => [],
         "processed" => 0,
         "conflicts" => [],
         "status" => "preparing"
       }}
    else
      {:error, :timeline_capacity}
    end
  end

  @spec batch(work :: map(), limit :: pos_integer()) :: term()
  def batch(%{"status" => "preparing"} = work, limit) when is_integer(limit) and limit in 1..64,
    do: process(work, limit)

  def batch(%{"status" => status} = work, _limit) when status in ["ready", "needs_review"],
    do: {:ok, work}

  def batch(_work, _limit), do: {:error, :invalid_timeline}

  defp process(work, 0), do: {:ok, work}

  defp process(%{"processed" => n} = work, _remaining) when n >= 1024,
    do: at_capacity(work)

  defp process(work, remaining) do
    due = due(work)
    record = Enum.at(work["records"], work["index"])

    cond do
      due && (is_nil(record) or elem(due, 2) <= record["at"]) -> due_step(work, due, remaining)
      record -> recorded_step(work, record, remaining)
      true -> {:ok, %{work | "status" => "ready"}}
    end
  end

  defp at_capacity(work) do
    if is_nil(due(work)) and work["index"] == length(work["records"]),
      do: {:ok, %{work | "status" => "ready"}},
      else: {:ok, conflict(work, %{"reason" => "timeline_capacity"})}
  end

  defp due(work) do
    work["states"]
    |> Enum.flat_map(fn {zone, state} ->
      case DueWork.next(state, work["target"]) do
        nil -> []
        {id, at} -> [{zone, id, at}]
      end
    end)
    |> Enum.min_by(fn {zone, id, at} -> {at, zone, id} end, fn -> nil end)
  end

  defp due_step(work, {zone, id, at}, remaining) do
    state = work["states"][zone]

    context =
      Map.new(work["states"], fn {id, scene} ->
        {id, DueWork.context_value(scene)}
      end)

    case DueWork.occur(state, id, at, work["calendar"], context) do
      {:ok, next, event} ->
        recorded = Enum.find(work["records"], &(&1["effect"][:id] == event.id))

        if is_nil(recorded) or
             (RecordedChange.equivalent?(next, recorded["after"]) and
                event.result == recorded["effect"].result) do
          work =
            work
            |> put_in(["states", zone], next)
            |> Map.update!("generated", &(&1 ++ [%{"zone" => zone, "event" => event}]))

          process(Map.update!(work, "processed", &(&1 + 1)), remaining - 1)
        else
          {:ok,
           conflict(work, %{
             "zone" => zone,
             "at" => at,
             "source_id" => recorded["source_id"],
             "reason" => "local_due_conflict"
           })}
        end

      {:error, reason} ->
        {:ok, conflict(work, %{"zone" => zone, "at" => at, "reason" => Atom.to_string(reason)})}
    end
  end

  defp recorded_step(work, record, remaining) do
    state = work["states"][record["zone"]]
    effect = record["effect"]

    result =
      if Map.has_key?(effect, :schedule_id) do
        if Enum.any?(work["generated"], &(&1["event"].id == effect.id)),
          do: {:ok, state},
          else: {:error, :local_due_conflict}
      else
        RecordedChange.apply(state, record["before"], record["after"], effect)
      end

    case result do
      {:ok, next} ->
        work =
          work
          |> put_in(["states", record["zone"]], next)
          |> Map.update!("index", &(&1 + 1))
          |> Map.update!("processed", &(&1 + 1))

        process(work, remaining - 1)

      {:error, reason} ->
        {:ok,
         conflict(work, %{
           "zone" => record["zone"],
           "at" => record["at"],
           "source_id" => record["source_id"],
           "reason" => Atom.to_string(reason)
         })}
    end
  end

  defp conflict(work, details),
    do: %{work | "status" => "needs_review", "conflicts" => work["conflicts"] ++ [details]}
end
