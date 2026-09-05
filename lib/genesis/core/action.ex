defmodule Genesis.Core.Action do
  @moduledoc "Validates only the bounded action configuration the scene reducer implements."
  alias Genesis.Core.{Check, Scope}

  @spec valid_set?(actions :: term()) :: boolean()
  def valid_set?(actions) when is_map(actions) and map_size(actions) <= 32,
    do: Enum.all?(actions, fn {id, action} -> Scope.id?(id) and valid?(action) end)

  def valid_set?(_actions), do: false

  @spec valid?(action :: term()) :: boolean()
  def valid?(
        %{"kind" => kind, "duration" => duration, "cost" => cost, "resource" => resource} = action
      ) do
    is_integer(duration) and duration in 0..31_536_000 and is_integer(cost) and
      cost in 0..1_000_000 and
      Scope.id?(resource) and fields?(kind, action)
  end

  def valid?(_action), do: false
  defp fields?("take", action), do: keys?(action, [])
  defp fields?("deed", action), do: keys?(action, ["fact"]) and Scope.id?(action["fact"])

  defp fields?("access", action),
    do: keys?(action, ["outcome"]) and action["outcome"] in ~w(admitted confrontation)

  defp fields?("check", action),
    do:
      keys?(action, ["check", "attribute"]) and Scope.id?(action["attribute"]) and
        Check.validate(action["check"]) == :ok

  defp fields?(_kind, _action), do: false

  defp keys?(action, extra) do
    allowed = ~w(kind duration cost resource capability) ++ extra

    Enum.all?(Map.keys(action), &(&1 in allowed)) and
      (not Map.has_key?(action, "capability") or Scope.id?(action["capability"]))
  end
end
