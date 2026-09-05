defmodule Genesis.Core.Modifiers do
  @moduledoc "Modifiers apply in ascending priority then stable ID order; cap is an explicit ordered operation."
  alias Genesis.Core.Scope

  @spec apply(base :: integer(), modifiers :: [map()]) ::
          {:ok, integer()} | {:error, :invalid_modifiers}
  def apply(base, modifiers)
      when is_integer(base) and abs(base) <= 1000 and is_list(modifiers) and
             length(modifiers) <= 32 do
    if Enum.all?(modifiers, &valid?/1) and
         length(Enum.uniq_by(modifiers, & &1["id"])) == length(modifiers) do
      modifiers
      |> Enum.sort_by(&{&1["priority"], &1["id"]})
      |> Enum.reduce_while({:ok, base}, &apply_one/2)
    else
      {:error, :invalid_modifiers}
    end
  end

  def apply(_base, _modifiers), do: {:error, :invalid_modifiers}

  defp apply_one(modifier, {:ok, current}) do
    value = change(current, modifier)
    if abs(value) <= 1000, do: {:cont, {:ok, value}}, else: {:halt, {:error, :invalid_modifiers}}
  end

  defp valid?(%{"id" => id, "priority" => priority, "mode" => mode, "value" => value} = modifier) do
    map_size(modifier) == 4 and Scope.id?(id) and is_integer(priority) and priority in 0..1000 and
      mode in ~w(add set min max) and is_integer(value) and abs(value) <= 1000
  end

  defp valid?(_modifier), do: false
  defp change(current, %{"mode" => "add", "value" => value}), do: current + value
  defp change(_current, %{"mode" => "set", "value" => value}), do: value
  defp change(current, %{"mode" => "min", "value" => value}), do: min(current, value)
  defp change(current, %{"mode" => "max", "value" => value}), do: max(current, value)
end
