defmodule Genesis.Core.DueWork do
  @moduledoc "Explicit-target, capped due work. Stable identities are independent of execution scope and chunk size."
  alias Genesis.Core.{FictionalTime, LocalAction, Schedule, State}
  alias Genesis.Time.Calendar

  @spec advance(
          state :: State.t(),
          target :: term(),
          calendar :: map(),
          limit :: pos_integer(),
          context :: map()
        ) :: term()
  def advance(state, target, calendar, limit, context \\ %{}) do
    if is_integer(target) and target >= state.time.value and
         target - state.time.value <= 31_622_400 and
         is_integer(limit) and limit in 1..64 and Schedule.timeline?(state.timeline) do
      run(state, target, calendar, limit, context, [])
    else
      {:error, :invalid_target}
    end
  end

  @spec next(state :: map(), target :: integer()) :: {String.t(), integer()} | nil
  def next(%{timeline: nil}, _target), do: nil

  def next(state, target),
    do:
      state.timeline["next"]
      |> Enum.filter(fn {_, at} -> is_integer(at) and at <= target end)
      |> Enum.min_by(fn {id, at} -> {at, id} end, fn -> nil end)

  defp run(state, target, calendar, remaining, context, events) do
    case next(state, target) do
      nil ->
        with {:ok, time} <-
               FictionalTime.advance(state.time, %{
                 unit: :second,
                 value: target - state.time.value
               }),
             do:
               {:ok, %{state | time: time, elapsed: state.elapsed + target - state.time.value},
                events, :done}

      _point when remaining == 0 ->
        {:ok, state, events, :more}

      {id, at} ->
        with {:ok, changed, event} <- occur(state, id, at, calendar, context),
             do: run(changed, target, calendar, remaining - 1, context, events ++ [event])
    end
  end

  @spec occur(
          state :: map(),
          id :: String.t(),
          at :: integer(),
          calendar :: map(),
          context :: map()
        ) :: term()
  def occur(state, id, at, calendar, context) do
    row = state.timeline["schedules"][id]
    context = Map.put(context, state.zone_id, context_value(state))

    with true <- state.timeline["next"][id] == at and at >= state.time.value,
         causes = causes(row, context),
         true <- causes.depth <= 8,
         {:ok, following} <- following(state, row, at, calendar),
         {:ok, positioned, [], :done} <- advance(%{state | timeline: nil}, at, calendar, 1) do
      positioned = %{positioned | timeline: state.timeline}
      event_id = occurrence_id(state, id, row["version"], at)
      {changed, effect} = resolve(positioned, row, event_id, context, calendar)
      timeline = put_in(changed.timeline["next"][id], following)

      effect =
        effect
        |> Map.put(:schedule_id, id)
        |> Map.put(:schedule_version, row["version"])
        |> Map.put(:causal_root_id, causes.root || event_id)
        |> Map.put(:causal_parent_ids, causes.parents)
        |> Map.put(:causal_depth, causes.depth)
        |> Map.update(:source_ids, causes.parents, &Enum.uniq(&1 ++ causes.parents))

      changed = %{
        changed
        | timeline: timeline.timeline,
          revision: state.revision + 1,
          events: state.events ++ [effect]
      }

      with {:ok, changed} <- State.restore(changed), do: {:ok, changed, effect}
    else
      false -> {:error, :invalid_occurrence}
      error -> error
    end
  end

  @spec context_value(state :: map()) :: map()
  def context_value(state) do
    condition = (state.timeline || %{})["condition"] || "normal"

    last =
      state.events
      |> Enum.reverse()
      |> Enum.find(&(&1.type == "scheduled_condition" and &1.result["status"] == "applied"))

    %{
      "condition" => condition,
      "source" => if(last, do: Map.take(last, [:id, :causal_root_id, :causal_depth]))
    }
  end

  defp causes(row, context) do
    source = if row["dependency"], do: get_in(context, [row["dependency"]["zone_id"], "source"])

    if source,
      do: %{
        root: source[:causal_root_id] || source.id,
        parents: [source.id],
        depth: Map.get(source, :causal_depth, 0) + 1
      },
      else: %{root: nil, parents: [], depth: 0}
  end

  @spec occurrence_id(
          state :: map(),
          schedule :: String.t(),
          version :: integer(),
          at :: integer()
        ) :: String.t()
  def occurrence_id(state, id, version, at),
    do:
      "due-" <>
        Base.encode16(
          :crypto.hash(
            :sha256,
            :erlang.term_to_binary(
              {state.scope.world_id, state.scope.generation, state.zone_id, id, version, at}
            )
          ),
          case: :lower
        )

  defp following(_state, %{"every" => nil}, _at, _calendar), do: {:ok, nil}

  defp following(state, row, at, calendar) do
    case row["every"] do
      nil ->
        {:ok, nil}

      amount ->
        with {:ok, seconds} <- Calendar.duration(%{state.time | value: at}, amount, calendar),
             true <- seconds > 0 do
          following = at + seconds
          {:ok, if(row["until"] && following > row["until"], do: nil, else: following)}
        else
          false -> {:error, :invalid_recurrence}
          error -> error
        end
    end
  end

  defp resolve(state, row, id, context, calendar) do
    if eligible?(state, row, context, calendar),
      do: lawful(state, row, id),
      else: skipped(state, row, id, "unavailable_at_occurrence")
  end

  defp eligible?(state, row, context, calendar) do
    span = row["availability"]
    dependency = row["dependency"]
    available = is_nil(span) or Calendar.contains?(state.time, span["from"], span["to"], calendar)

    related =
      is_nil(dependency) or
        get_in(context, [dependency["zone_id"], "condition"]) == dependency["condition"]

    available and related and Schedule.actor?(state, row)
  end

  defp lawful(state, %{"action" => "condition"} = row, id) do
    changed = put_in(state.timeline["condition"], row["condition"])
    {changed, event(state, row, id, %{"status" => "applied", "condition" => row["condition"]})}
  end

  defp lawful(state, row, id) do
    inputs = %{event_id: id, draws: [], recorded_at: nil}

    case LocalAction.scheduled(state, row["actor_id"], Schedule.intent(row), inputs) do
      {:ok, changed, [effect]} ->
        {changed,
         effect
         |> Map.put(:type, "scheduled_" <> row["action"])
         |> Map.update!(:result, &Map.put(&1, "status", "applied"))}

      {:error, reason} ->
        skipped(state, row, id, Atom.to_string(reason))
    end
  end

  defp skipped(state, row, id, reason),
    do: {state, event(state, row, id, %{"status" => "skipped", "reason" => reason})}

  defp event(state, row, id, result),
    do: %{
      id: id,
      type: "scheduled_" <> row["action"],
      actor_id: row["actor_id"],
      target_id: row["target_id"] || state.zone_id,
      scope: state.scope,
      audience: :gm,
      revision: state.revision + 1,
      occurred_at: state.time.value,
      recorded_at: nil,
      source_ids: [],
      result: result
    }
end
