defmodule Genesis.Core.StandingTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.Standing

  test "sources deduplicate and aggregate visibility cannot disclose a private contribution" do
    assert {:ok, first} = Standing.report(Standing.new(), "offering", ["gm", "mara"])
    assert first["standing"] == 1 and first["relief_supported"]
    assert {:ok, ^first} = Standing.report(first, "offering", ["stranger"])
    assert {:ok, next} = Standing.report(first, "private-offering", ["gm"])
    assert next["standing"] == 2
    assert next["audience_users"] == ["gm"]
    refute Standing.valid?(Map.put(next, "standing", 201))
  end
end
