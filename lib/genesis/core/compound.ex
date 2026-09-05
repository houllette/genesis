defmodule Genesis.Core.Compound do
  @moduledoc "Sequential bounded plans preserve accepted steps and stop on first rejection. No IO or retry loop."
  alias Genesis.Core.{Scene, State}

  @spec run(state :: State.t(), actor_id :: String.t(), steps :: [{map(), map()}]) ::
          {:ok, State.t(), [map()]}
          | {:partial, State.t(), [map()], non_neg_integer(), atom()}
          | {:error, :invalid_plan}
  def run(state, actor_id, steps) when is_list(steps) and length(steps) in 1..8 do
    steps
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, state, []}, fn {{intent, inputs}, index},
                                              {:ok, current, effects} ->
      inputs = Map.put(inputs, :expected_revision, current.revision)

      case Scene.reduce(current, actor_id, intent, inputs) do
        {:ok, next, emitted} -> {:cont, {:ok, next, effects ++ emitted}}
        {:error, reason} -> {:halt, {:partial, current, effects, index, reason}}
      end
    end)
  end

  def run(_state, _actor_id, _steps), do: {:error, :invalid_plan}
end
