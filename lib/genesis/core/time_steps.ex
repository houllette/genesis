defmodule Genesis.Core.TimeSteps do
  @moduledoc "Bounded recorded due transitions followed by one explicit target coordinate."
  alias Genesis.Core.{DueWork, FictionalTime}

  @spec prepare(
          state :: map(),
          target :: integer(),
          calendar :: map(),
          context :: map(),
          limit :: integer()
        ) :: term()
  def prepare(state, target, calendar, context, limit \\ 64) do
    with true <-
           is_integer(target) and target >= state.time.value and
             target - state.time.value <= 31_622_400 and is_integer(limit) and limit in 1..64,
         {:ok, current, steps} <- steps(state, target, calendar, context, limit, []),
         {:ok, time} <-
           FictionalTime.advance(current.time, %{
             unit: :second,
             value: target - current.time.value
           }) do
      next = %{
        current
        | time: time,
          elapsed: current.elapsed + target - current.time.value,
          revision: current.revision + 1
      }

      {:ok, current, next, steps}
    else
      false -> {:error, :invalid_target}
      error -> error
    end
  end

  defp steps(state, target, calendar, context, remaining, acc) do
    case DueWork.next(state, target) do
      nil ->
        {:ok, state, acc}

      _point when remaining == 0 ->
        {:error, :due_work_capacity}

      {id, at} ->
        with {:ok, next, event} <- DueWork.occur(state, id, at, calendar, context),
             do:
               steps(
                 next,
                 target,
                 calendar,
                 Map.put(context, state.zone_id, DueWork.context_value(next)),
                 remaining - 1,
                 acc ++ [%{before: state, next: next, event: event}]
               )
    end
  end
end
