defmodule Genesis.Core.FormulaTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Formula, Modifiers}

  test "derived dependencies resolve independently of map order; unsafe formulas fail" do
    formulas = %{
      "vigor" => ["mul", ["ref", "might"], 2],
      "capacity" => ["add", ["ref", "vigor"], 3]
    }

    assert {:ok, %{"might" => 4, "vigor" => 8, "capacity" => 11}} =
             Formula.derive(formulas, %{"might" => 4})

    assert {:ok, -2} = Formula.evaluate(["div", -5, 2], %{})
    assert {:error, :division_by_zero} = Formula.evaluate(["div", 1, 0], %{})

    assert {:error, :cycle_or_missing_reference} =
             Formula.derive(%{"a" => ["ref", "b"], "b" => ["ref", "a"]}, %{})

    assert {:error, :cycle_or_missing_reference} =
             Formula.derive(%{"a" => ["ref", "missing"]}, %{})

    assert {:error, :invalid_formula} = Formula.evaluate(["eval", "System.cmd"], %{})
    deep = Enum.reduce(1..20, 1, fn _, acc -> ["add", 1, acc] end)
    assert {:error, :formula_limit} = Formula.evaluate(deep, %{})
    assert {:error, :formula_limit} = Formula.evaluate(["mul", 1_000_000_000, 2], %{})
  end

  test "priority, replacement and caps compose deterministically and reject duplicate IDs" do
    modifiers = [
      %{"id" => "base", "priority" => 1, "mode" => "set", "value" => 4},
      %{"id" => "trait", "priority" => 2, "mode" => "add", "value" => 3},
      %{"id" => "cap", "priority" => 3, "mode" => "min", "value" => 6}
    ]

    assert {:ok, 6} = Modifiers.apply(0, Enum.reverse(modifiers))
    assert {:error, :invalid_modifiers} = Modifiers.apply(0, modifiers ++ [hd(modifiers)])
  end
end
