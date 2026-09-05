defmodule Genesis.Engine.Draws do
  @moduledoc "Shell randomness, sampled only after command validation and recorded by the reducer."
  @spec roll(check :: map()) :: [integer()]
  def roll(%{"mode" => "roll_over", "sides" => sides} = check) do
    extra = if Map.get(check, "explode", false), do: Map.get(check, "max_explosions", 0), else: 0
    exploding(sides, extra)
  end

  def roll(%{"mode" => "pbta"}), do: [:rand.uniform(6), :rand.uniform(6)]

  def roll(%{"mode" => "pool", "count" => count, "sides" => sides}),
    do: Enum.map(1..count, fn _ -> :rand.uniform(sides) end)

  def roll(%{"mode" => "fudge"}), do: Enum.map(1..4, fn _ -> :rand.uniform(3) - 2 end)

  defp exploding(sides, extra) do
    draw = :rand.uniform(sides)
    if draw == sides and extra > 0, do: [draw | exploding(sides, extra - 1)], else: [draw]
  end
end
