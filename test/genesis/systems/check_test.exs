defmodule Genesis.Core.CheckTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.Check

  test "roll-over boundaries on d20 and d10 use supplied draws" do
    for sides <- [10, 20], draw <- 1..sides do
      assert {:ok, result} =
               Check.resolve(
                 %{"mode" => "roll_over", "sides" => sides, "target" => 8, "modifier" => 2},
                 [draw]
               )

      assert result.total == draw + 2
      assert result.outcome == if(draw + 2 >= 8, do: :success, else: :failure)
      assert result.draws == [draw]
    end
  end

  test "2d6, pools and Fudge enumerate exact finite boundaries" do
    for a <- 1..6, b <- 1..6 do
      assert {:ok, result} =
               Check.resolve(%{"mode" => "pbta", "partial" => 7, "full" => 10}, [a, b])

      expected =
        cond do
          a + b >= 10 -> :success
          a + b >= 7 -> :partial
          true -> :failure
        end

      assert result.outcome == expected

      assert {:ok, pool} =
               Check.resolve(
                 %{
                   "mode" => "pool",
                   "count" => 2,
                   "sides" => 6,
                   "success_at" => 5,
                   "target" => 1
                 },
                 [a, b]
               )

      assert pool.total == Enum.count([a, b], &(&1 >= 5))
    end

    for a <- -1..1, b <- -1..1, c <- -1..1, d <- -1..1 do
      assert {:ok, result} = Check.resolve(%{"mode" => "fudge", "target" => 0}, [a, b, c, d])
      assert result.total == a + b + c + d
    end
  end

  test "explosions stop at a recorded cap and reject missing, excessive or invalid draws" do
    spec = %{
      "mode" => "roll_over",
      "sides" => 10,
      "target" => 15,
      "explode" => true,
      "max_explosions" => 2
    }

    assert {:ok, %{total: 30, capped: true, draws: [10, 10, 10]}} =
             Check.resolve(spec, [10, 10, 10])

    assert {:ok, %{total: 13, capped: false}} = Check.resolve(spec, [10, 3])

    for draws <- [[10], [10, 3, 2], [0], [11], [1.0]] do
      assert {:error, _} = Check.resolve(spec, draws)
    end

    assert {:error, :invalid_check} = Check.resolve(Map.put(spec, "eval", "System.cmd"), [1])

    assert {:error, :invalid_check} =
             Check.resolve(
               %{
                 "mode" => "pool",
                 "count" => 1000,
                 "sides" => 6,
                 "target" => 1,
                 "success_at" => 5
               },
               []
             )
  end
end
