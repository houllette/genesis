defmodule Genesis.Core.NetworkTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.Network

  setup do
    catalog = %{
      world_id: "ashfall",
      generation: 2,
      zones: Map.new(~w(bridge docks ridge), &{&1, %{id: &1}}),
      institutions: %{"relief" => %{home_zone: "bridge", local_id: "settlement"}}
    }

    {:ok, %{catalog: catalog, data: Network.new("ashfall", 2)}}
  end

  test "directed cycles are legal, self links and duplicate edges are not", ctx do
    {:ok, data} = Network.apply(ctx.data, connection("bridge", "docks"), ctx.catalog)
    {:ok, data} = Network.apply(data, connection("docks", "ridge"), ctx.catalog)
    {:ok, data} = Network.apply(data, connection("ridge", "bridge"), ctx.catalog)
    assert length(data["connections"]) == 3
    assert :ok = Network.assess(data, "bridge", "docks", 4)
    assert {:error, :route_unavailable} = Network.assess(data, "docks", "bridge", 1)

    assert {:error, :invalid_connection} =
             Network.apply(data, connection("bridge", "bridge"), ctx.catalog)

    assert {:error, :invalid_network} =
             Network.restore(
               %{data | "connections" => data["connections"] ++ data["connections"]},
               ctx.catalog
             )
  end

  test "damage and capacity change assessment without moving any entities", ctx do
    for condition <- ~w(open damaged closed), size <- 1..5 do
      command = Map.put(connection("bridge", "docks"), "condition", condition)
      assert {:ok, data} = Network.apply(ctx.data, command, ctx.catalog)
      result = Network.assess(data, "bridge", "docks", size)

      expected =
        cond do
          condition != "open" -> {:error, :route_unavailable}
          size > 4 -> {:error, :capacity_exceeded}
          true -> :ok
        end

      assert result == expected
    end

    for size <- [0, -1, 1001, 1.5, "2", nil],
        do:
          assert(
            {:error, :invalid_party_size} = Network.assess(ctx.data, "bridge", "docks", size)
          )
  end

  test "closed format and world generation fences reject malformed or foreign data", ctx do
    for data <- [
          nil,
          [],
          %{},
          Map.put(ctx.data, "version", 99),
          Map.put(ctx.data, "generation", 1),
          Map.put(ctx.data, "world_id", "other"),
          Map.put(ctx.data, "stock", %{}),
          Map.put(ctx.data, "connections", [nil]),
          Map.put(ctx.data, "institutions", %{"x" => nil})
        ] do
      assert {:error, :invalid_network} = Network.restore(data, ctx.catalog)
    end

    for change <- [
          %{"to" => "foreign"},
          %{"capacity" => nil},
          %{"capacity" => 1.5},
          %{"visibility" => "party"},
          %{"condition" => "teleport"},
          %{"stock" => 30}
        ] do
      assert {:error, :invalid_connection} =
               Network.apply(
                 ctx.data,
                 Map.merge(connection("bridge", "docks"), change),
                 ctx.catalog
               )
    end
  end

  test "institution promotion preserves its local identity and includes its home jurisdiction",
       ctx do
    command = %{
      "type" => "jurisdiction",
      "institution_id" => "relief",
      "zones" => ["bridge", "docks"],
      "visibility" => "gm"
    }

    assert {:ok, data} = Network.apply(ctx.data, command, ctx.catalog)

    assert data["institutions"]["relief"] == %{
             "home_zone" => "bridge",
             "local_id" => "settlement",
             "zones" => ["bridge", "docks"],
             "visibility" => "gm"
           }

    for zones <- [[], ["docks"], ["bridge", "foreign"], ["bridge", "bridge"], nil] do
      assert {:error, :invalid_network} =
               Network.apply(ctx.data, %{command | "zones" => zones}, ctx.catalog)
    end

    assert {:error, :invalid_jurisdiction} =
             Network.apply(ctx.data, %{command | "institution_id" => "imaginary"}, ctx.catalog)

    assert {:error, :invalid_jurisdiction} =
             Network.apply(ctx.data, Map.put(command, "stock", 50), ctx.catalog)

    altered = put_in(data["institutions"]["relief"]["local_id"], "replacement")
    assert {:error, :invalid_network} = Network.restore(altered, ctx.catalog)
  end

  test "edge work is bounded at 160 links", ctx do
    zones = for n <- 1..20, into: %{}, do: {"z#{n}", %{}}
    catalog = %{ctx.catalog | zones: zones}
    commands = for a <- 1..20, b <- 1..20, a != b, do: connection("z#{a}", "z#{b}")
    {admitted, [overflow | _]} = Enum.split(commands, 160)

    data =
      Enum.reduce(admitted, ctx.data, fn command, data ->
        assert {:ok, next} = Network.apply(data, command, catalog)
        next
      end)

    assert length(data["connections"]) == 160
    assert {:error, :invalid_network} = Network.apply(data, overflow, catalog)

    assert {:ok, updated} =
             Network.apply(data, Map.put(hd(admitted), "condition", "closed"), catalog)

    assert length(updated["connections"]) == 160
  end

  defp connection(from, to),
    do: %{
      "type" => "connection",
      "from" => from,
      "to" => to,
      "condition" => "open",
      "capacity" => 4,
      "visibility" => "public"
    }
end
