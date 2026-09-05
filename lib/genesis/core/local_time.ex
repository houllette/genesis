defmodule Genesis.Core.LocalTime do
  @moduledoc "Explicit local-time contributions and completion totals. No clocks or publication authority."
  alias Genesis.Core.{FictionalTime, State}

  @max_elapsed 31_622_400

  @spec elapse(state :: State.t(), seconds :: non_neg_integer()) ::
          {:ok, State.t()} | {:error, atom()}
  def elapse(%{scope: %{kind: :experience}, status: :active} = state, seconds)
      when is_integer(seconds) and seconds >= 0 do
    with true <- state.elapsed + seconds <= @max_elapsed,
         {:ok, time} <- FictionalTime.advance(state.time, %{unit: :second, value: seconds}) do
      {:ok, %{state | time: time, elapsed: state.elapsed + seconds, revision: state.revision + 1}}
    else
      false -> {:error, :time_capacity_limit}
      error -> error
    end
  end

  def elapse(_state, _seconds), do: {:error, :invalid_local_time}

  @spec contribution(before :: State.t(), next :: State.t()) :: map()
  def contribution(before, next),
    do: %{
      "format" => 1,
      "from" => before.time.value,
      "to" => next.time.value,
      "elapsed_before" => before.elapsed,
      "elapsed_after" => next.elapsed,
      "seconds" => next.elapsed - before.elapsed,
      "calendar_id" => before.time.calendar_id,
      "calendar_version" => before.time.calendar_version,
      "unit" => "second"
    }

  @spec declaration(attrs :: term(), recorded_elapsed :: non_neg_integer()) ::
          {:ok, map()} | {:error, atom()}
  def declaration(
        %{"elapsed_seconds" => total, "outcome" => outcome, "reason" => reason} = attrs,
        recorded
      ) do
    cond do
      not valid_declaration?(attrs, total, outcome, reason) -> {:error, :invalid_completion}
      total < recorded -> {:error, :duration_before_recorded_time}
      true -> {:ok, attrs}
    end
  end

  def declaration(_attrs, _recorded), do: {:error, :invalid_completion}

  @spec reason?(value :: term()) :: boolean()
  def reason?(value),
    do:
      is_binary(value) and String.valid?(value) and
        byte_size(value) in 1..2048 and String.trim(value) != ""

  defp valid_declaration?(attrs, total, outcome, reason),
    do:
      Enum.all?(
        Map.keys(attrs),
        &(&1 in ~w(elapsed_seconds outcome reason review_required basis))
      ) and
        is_binary(attrs["basis"]) and byte_size(attrs["basis"]) == 64 and
        is_integer(total) and total in 0..@max_elapsed and
        outcome in ~w(completed failed abandoned) and
        reason?(reason) and is_boolean(Map.get(attrs, "review_required", false))
end
