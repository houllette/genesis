defmodule Genesis.Core.SceneTest do
  use ExUnit.Case, async: true
  import Genesis.SceneFixtures
  alias Genesis.Core.{Scene, State}

  test "take conserves identity and quantity, with deterministic ordered effects" do
    state = scene()
    intent = %{type: "take", target_id: "ration"}
    assert {:ok, next, [effect]} = Scene.reduce(state, "mara", intent, inputs(state, "take-1"))
    assert next.items["ration"].owner == {:actor, "mara"}
    assert next.items["ration"].quantity == 2
    assert state.items["ration"].owner == {:zone, "bridge"}
    assert next.revision == 1
    assert effect.id == "take-1"
    assert {:ok, [%{id: "ration", quantity: 2}]} = State.inventory(next, "mara")
    assert Scene.reduce(state, "mara", intent, inputs(state, "take-1")) == {:ok, next, [effect]}
    assert {:error, :unavailable} = Scene.reduce(next, "courier", intent, inputs(next, "take-2"))
  end

  test "hidden and missing targets have identical rejection; player projections omit metadata" do
    state = scene()

    for target <- ["sealed-letter", "not-there"] do
      assert {:error, :unavailable} =
               Scene.reduce(
                 state,
                 "mara",
                 %{type: "take", target_id: target},
                 inputs(state, target)
               )
    end

    assert {:ok, player} = State.view(state, %{role: :player, actor_id: "mara"})
    assert {:ok, courier} = State.view(state, %{role: :player, actor_id: "courier"})
    assert {:ok, gm} = State.view(state, %{role: :gm})
    assert Enum.map(player.items, & &1.id) == ["ration"]
    assert Enum.map(player.knowledge, & &1.id) == ["rumor"]
    assert courier.knowledge == []
    assert Enum.any?(gm.knowledge, &(&1.id == "secret"))
    refute inspect(player) =~ "authored-secret"
    refute inspect(player) =~ "friendship"
  end
end
