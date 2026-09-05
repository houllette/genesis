defmodule Genesis.Core.TransferTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Curation, Scene, State, Stock, Transfer}
  import Genesis.SceneFixtures

  test "an actor, every carried item and self-contained beliefs move once, without changing fiction" do
    source = scene()
    source = put_in(source.items["ration"].owner, {:actor, "mara"})
    destination = %{source | zone_id: "docks", actors: %{}, items: %{}, knowledge: %{}}
    assert {:ok, left, right} = Transfer.move(source, destination, "mara")
    refute Map.has_key?(left.actors, "mara")
    assert right.actors["mara"] == source.actors["mara"]
    refute Map.has_key?(left.items, "ration")
    assert right.items["ration"] == source.items["ration"]
    assert right.knowledge["rumor"] == source.knowledge["rumor"]
    assert {:ok, %{knowledge: []}} = State.view(right, %{role: :spectator, actor_id: nil})
    refute Map.has_key?(left.knowledge, "rumor")
    assert left.knowledge["secret"] == source.knowledge["secret"]
    assert left.time == right.time and right.time == source.time
    assert {:ok, ^left} = State.restore(left)
    assert {:ok, ^right} = State.restore(right)
  end

  test "commodity holdings can cross a place without a market but cannot create an exchange there" do
    source = Genesis.SettlementFixtures.scene()

    destination = %{
      source
      | zone_id: "docks",
        actors: %{},
        items: %{},
        knowledge: %{},
        settlement: nil
    }

    assert {:ok, left, right} = Transfer.move(source, destination, "mara")
    assert Stock.balance(right, "mara", "coin") == 100
    assert Stock.balance(left, "mara", "coin") == 0
    assert Stock.balance(right, "mara", "grain") == 2

    assert {:error, _} =
             Curation.apply(right, "mint", %{
               "kind" => "stock",
               "name" => "Coin",
               "commodity" => "coin",
               "quantity" => 5,
               "owner_id" => "mara",
               "reason" => "forged"
             })

    assert {:error, _} =
             Scene.propose(
               right,
               "mara",
               %{type: "buy", target_id: "mara", quantity: 1},
               "buy"
             )

    invalid = put_in(right.items["mara-coin"].commodity, "unknown")
    assert {:error, :invalid_state} = State.restore(invalid)
  end

  test "cross-place knowledge is retained; uncommitted followers, anchored NPCs and collisions fail closed" do
    source = scene()
    destination = %{source | zone_id: "docks", actors: %{}, items: %{}, knowledge: %{}}
    linked = put_in(source.knowledge["rumor"].object_id, "moll")
    assert {:ok, _left, right} = Transfer.move(linked, destination, "mara")
    assert right.actor_refs == ["moll"]
    assert right.knowledge["rumor"] == linked.knowledge["rumor"]
    incoming = put_in(source.knowledge["secret"].object_id, "mara")
    assert {:ok, left, _right} = Transfer.move(incoming, destination, "mara")
    assert left.actor_refs == ["mara"]
    assert left.knowledge["secret"] == incoming.knowledge["secret"]
    companion = put_in(source.actors["moll"].companion_of, "mara")
    assert {:error, :companion_unavailable} = Transfer.move(companion, destination, "mara")
    local = Genesis.SettlementFixtures.scene()

    assert {:error, :cross_zone_dependency} =
             Transfer.move(
               local,
               %{
                 local
                 | zone_id: "docks",
                   actors: %{},
                   items: %{},
                   knowledge: %{},
                   settlement: nil
               },
               "moll"
             )

    destination = %{destination | actors: %{"rumor" => %{source.actors["courier"] | id: "rumor"}}}
    assert {:error, :identity_collision} = Transfer.move(source, destination, "mara")
  end

  test "different scopes, pause and elapsed fiction are not silently reconciled" do
    source = scene()
    destination = %{source | zone_id: "docks", actors: %{}, items: %{}, knowledge: %{}}

    assert {:error, :invalid_scope} =
             Transfer.move(
               source,
               %{destination | scope: %{destination.scope | id: "other"}},
               "mara"
             )

    assert {:error, :paused} = Transfer.move(State.pause(source), destination, "mara")

    assert {:error, :time_reconciliation_unavailable} =
             Transfer.move(%{source | elapsed: 1}, destination, "mara")
  end
end
