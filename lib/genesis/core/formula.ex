defmodule Genesis.Core.Formula do
  @moduledoc "Integer-only expression trees: ref, add, subtract, multiply, divide, min and max. Division truncates toward zero."
  alias Genesis.Core.Scope
  @limit 1_000_000_000

  @spec evaluate(expression :: term(), values :: map()) :: {:ok, integer()} | {:error, atom()}
  def evaluate(expression, values) when is_map(values) do
    with {:ok, result, _budget} <- walk(expression, values, 0, 128), do: {:ok, result}
  end

  def evaluate(_expression, _values), do: {:error, :invalid_formula}

  @spec derive(formulas :: map(), values :: map()) :: {:ok, map()} | {:error, atom()}
  def derive(formulas, values)
      when is_map(formulas) and map_size(formulas) <= 32 and is_map(values) do
    names = Map.keys(formulas)

    if Enum.all?(names, &(Scope.id?(&1) and not Map.has_key?(values, &1))) do
      derive_remaining(Enum.sort(formulas), values)
    else
      {:error, :invalid_formula}
    end
  end

  def derive(_formulas, _values), do: {:error, :invalid_formula}

  defp derive_remaining([], values), do: {:ok, values}

  defp derive_remaining(pending, values) do
    result =
      Enum.reduce_while(pending, {:ok, [], values}, fn {name, expression},
                                                       {:ok, waiting, current} ->
        case evaluate(expression, current) do
          {:ok, value} -> {:cont, {:ok, waiting, Map.put(current, name, value)}}
          {:error, :missing_reference} -> {:cont, {:ok, waiting ++ [{name, expression}], current}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, ^pending, _values} -> {:error, :cycle_or_missing_reference}
      {:ok, waiting, current} -> derive_remaining(waiting, current)
      error -> error
    end
  end

  defp walk(_expression, _values, depth, budget) when depth > 16 or budget <= 0,
    do: {:error, :formula_limit}

  defp walk(value, _values, _depth, budget) when is_integer(value) and abs(value) <= @limit,
    do: {:ok, value, budget - 1}

  defp walk(["ref", name], values, _depth, budget) when is_binary(name) do
    case Map.fetch(values, name) do
      {:ok, value} when is_integer(value) and abs(value) <= @limit -> {:ok, value, budget - 1}
      :error -> {:error, :missing_reference}
      _ -> {:error, :invalid_formula}
    end
  end

  defp walk([operator, left, right], values, depth, budget)
       when operator in ~w(add sub mul div min max) do
    with {:ok, a, remaining} <- walk(left, values, depth + 1, budget - 1),
         {:ok, b, remaining} <- walk(right, values, depth + 1, remaining),
         {:ok, result} <- operation(operator, a, b) do
      if abs(result) <= @limit, do: {:ok, result, remaining}, else: {:error, :formula_limit}
    end
  end

  defp walk(_expression, _values, _depth, _budget), do: {:error, :invalid_formula}
  defp operation("add", a, b), do: {:ok, a + b}
  defp operation("sub", a, b), do: {:ok, a - b}
  defp operation("mul", a, b), do: {:ok, a * b}
  defp operation("div", _a, 0), do: {:error, :division_by_zero}
  defp operation("div", a, b), do: {:ok, div(a, b)}
  defp operation("min", a, b), do: {:ok, min(a, b)}
  defp operation("max", a, b), do: {:ok, max(a, b)}
end
