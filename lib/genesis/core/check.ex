defmodule Genesis.Core.Check do
  @moduledoc "Bounded dice checks with supplied draws. No random generator or executable grammar."
  @spec resolve(spec :: map(), draws :: [integer()]) :: {:ok, map()} | {:error, atom()}
  def resolve(spec, draws) when is_list(draws) and length(draws) <= 100 do
    with :ok <- validate(spec),
         {:ok, total, capped} <- total(spec, draws) do
      total = total + Map.get(spec, "modifier", 0)
      {:ok, %{total: total, outcome: outcome(spec, total), draws: draws, capped: capped}}
    end
  end

  def resolve(_spec, _draws), do: {:error, :invalid_check}

  @doc "An attribute adds dice to a pool and adds to the total in other modes; resulting limits still apply."
  @spec prepare(spec :: map(), attribute :: integer()) :: {:ok, map()} | {:error, :invalid_check}
  def prepare(spec, attribute) when is_integer(attribute) and attribute in 0..1000 do
    with :ok <- validate(spec) do
      key = if spec["mode"] == "pool", do: "count", else: "modifier"
      prepared = Map.update(spec, key, attribute, &(&1 + attribute))
      with :ok <- validate(prepared), do: {:ok, prepared}
    end
  end

  def prepare(_spec, _attribute), do: {:error, :invalid_check}

  @spec validate(spec :: term()) :: :ok | {:error, :invalid_check}
  def validate(%{"mode" => mode} = spec) do
    modifier = Map.get(spec, "modifier", 0)

    if is_integer(modifier) and modifier in -1000..1000 and valid_mode?(mode, spec),
      do: :ok,
      else: {:error, :invalid_check}
  end

  def validate(_spec), do: {:error, :invalid_check}

  defp valid_mode?("roll_over", spec) do
    keys?(spec, ~w(mode sides target modifier explode max_explosions)) and
      integer?(spec["sides"], 2..100) and integer?(spec["target"], -1000..10_000) and
      is_boolean(Map.get(spec, "explode", false)) and
      integer?(Map.get(spec, "max_explosions", 0), 0..20)
  end

  defp valid_mode?("pbta", spec),
    do:
      keys?(spec, ~w(mode partial full modifier)) and
        integer?(spec["partial"], -1000..1000) and integer?(spec["full"], -1000..1000) and
        spec["partial"] < spec["full"]

  defp valid_mode?("pool", spec),
    do:
      keys?(spec, ~w(mode count sides success_at target)) and
        integer?(spec["count"], 1..100) and integer?(spec["sides"], 2..100) and
        integer?(spec["success_at"], 1..spec["sides"]) and
        integer?(spec["target"], 0..spec["count"])

  defp valid_mode?("fudge", spec),
    do: keys?(spec, ~w(mode target modifier)) and integer?(spec["target"], -1000..1000)

  defp valid_mode?(_mode, _spec), do: false
  defp keys?(spec, allowed), do: Enum.all?(Map.keys(spec), &(&1 in allowed))
  defp integer?(value, range), do: is_integer(value) and value in range

  defp total(%{"mode" => "roll_over", "sides" => sides} = spec, draws) do
    if Map.get(spec, "explode", false),
      do: explode(draws, sides, Map.get(spec, "max_explosions", 0), 0),
      else: sum(draws, 1, 1..sides)
  end

  defp total(%{"mode" => "pbta"}, draws), do: sum(draws, 2, 1..6)
  defp total(%{"mode" => "fudge"}, draws), do: sum(draws, 4, -1..1)

  defp total(
         %{"mode" => "pool", "count" => count, "sides" => sides, "success_at" => threshold},
         draws
       ) do
    with {:ok, _total, false} <- sum(draws, count, 1..sides) do
      {:ok, Enum.count(draws, &(&1 >= threshold)), false}
    end
  end

  defp sum(draws, count, range) do
    if length(draws) == count and Enum.all?(draws, &integer?(&1, range)),
      do: {:ok, Enum.sum(draws), false},
      else: {:error, :invalid_draws}
  end

  defp explode([draw | rest], sides, remaining, total)
       when is_integer(draw) and draw >= 1 and draw <= sides do
    cond do
      draw == sides and remaining > 0 -> explode(rest, sides, remaining - 1, total + draw)
      rest != [] -> {:error, :unused_draws}
      true -> {:ok, total + draw, draw == sides}
    end
  end

  defp explode(_draws, _sides, _remaining, _total), do: {:error, :invalid_draws}
  defp outcome(%{"mode" => "pbta", "full" => full}, total) when total >= full, do: :success

  defp outcome(%{"mode" => "pbta", "partial" => partial}, total) when total >= partial,
    do: :partial

  defp outcome(%{"mode" => "pbta"}, _total), do: :failure
  defp outcome(%{"target" => target}, total) when total >= target, do: :success
  defp outcome(_spec, _total), do: :failure
end
