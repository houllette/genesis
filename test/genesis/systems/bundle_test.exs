defmodule Genesis.Systems.BundleTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.Scene
  alias Genesis.SceneFixtures
  alias Genesis.Systems
  alias Genesis.Systems.{Bundle, Declarative}

  test "both original bundles load with distinct rules and stable content references" do
    assert {:ok, fantasy} = Systems.load("fantasy_demo")
    assert {:ok, cyber} = Systems.load("cyberpunk_demo")
    assert fantasy.data["actions"]["attempt"]["check"]["sides"] == 20
    assert cyber.data["actions"]["attempt"]["check"]["sides"] == 10
    assert fantasy.ref != cyber.ref
    assert Systems.load("fantasy_demo") == {:ok, fantasy}
    assert {:error, :unknown_bundle} = Systems.load("../config/runtime")
  end

  test "malformed bundles, invalid defaults, references, durations and unsupported mechanics fail" do
    {:ok, bundle} = Systems.load("fantasy_demo")
    data = bundle.data

    invalid = [
      Map.put(data, "code", "arbitrary"),
      Map.put(data, "attributes", data["attributes"] ++ data["attributes"]),
      put_in(data["actions"]["take"]["resource"], "money"),
      put_in(data["actions"]["take"]["kind"], "teleport"),
      put_in(data["actions"]["take"]["duration"], %{"unit" => "month", "value" => 1}),
      put_in(data["items"]["staff"]["slot"], "missing"),
      put_in(data["capabilities"]["commerce"]["enabled"], true),
      put_in(data["capabilities"]["scene"]["requires"], ["missing"]),
      Map.put(data, "resources", [%{"id" => "effort", "max" => 5, "default" => 6}]),
      Map.put(data, "resources", [
        %{"id" => "effort", "max" => ["ref", "missing"], "default" => 1}
      ]),
      Map.put(data, "context_rules", [
        Map.put(hd(data["context_rules"]), "when", %{"kind" => "trait", "key" => "king"})
      ])
    ]

    for changed <- invalid, do: assert({:error, :invalid_bundle} = Bundle.validate(changed))
    reordered = data |> Enum.reverse() |> Map.new()
    assert {:ok, ^bundle} = Bundle.validate(reordered)
    assert {:error, :unsupported_capability} = Systems.capability(bundle, "commerce")
    assert {:error, :unsupported_capability} = Systems.capability(bundle, "lore")

    cyclic =
      data
      |> put_in(["capabilities", "scene", "requires"], ["checks"])
      |> put_in(["capabilities", "checks", "requires"], ["scene"])

    assert {:error, :invalid_bundle} = Bundle.validate(cyclic)

    assert {:error, :invalid_bundle} =
             Bundle.validate(put_in(data["progression"]["milestone"]["fact"], "unknown-deed"))
  end

  test "one sheet path enforces pins, bounds and equipment for both systems; failed checks pay declared costs" do
    for {id, slot, item, roll} <- [
          {"fantasy_demo", "hand", "staff", 10},
          {"cyberpunk_demo", "implant", "interface", 6}
        ] do
      {:ok, bundle} = Systems.load(id)
      assert {:ok, sheet} = Systems.character(bundle, %{"equipment" => %{slot => item}})
      assert Declarative.metadata(bundle)["slots"] == bundle.data["slots"]
      assert :ok = Declarative.validate_character(bundle, sheet)

      assert {:ok, next, %{outcome: :success}} =
               Declarative.resolve(bundle, sheet, "attempt", [roll])

      resource = bundle.data["actions"]["attempt"]["resource"]
      assert next["resources"][resource] == sheet["resources"][resource] - 1

      assert {:ok, failed, %{outcome: :failure}} =
               Declarative.resolve(bundle, sheet, "attempt", [1])

      assert failed == next
      assert {:error, :invalid_draws} = Declarative.resolve(bundle, sheet, "attempt", [0])

      assert {:error, :invalid_character} =
               Declarative.validate_character(bundle, put_in(sheet["resources"][resource], -1))

      assert {:error, :invalid_character} =
               Systems.character(bundle, %{"equipment" => %{"wrong" => item}})

      assert {:error, :invalid_character} =
               Declarative.validate_character(bundle, put_in(sheet["bundle"]["version"], 99))

      assert {:error, :invalid_character} =
               Systems.character(bundle, %{"traits" => ["invented-title"]})

      assert {:error, :unsupported_action} =
               Declarative.resolve(bundle, sheet, "hack-universe", [20])
    end
  end

  test "both bundle configurations drive the same contextual scene reducer" do
    for {id, trait, cost} <- [
          {"fantasy_demo", "riverborn", 1},
          {"cyberpunk_demo", "guild-trained", 0}
        ] do
      {:ok, bundle} = Systems.load(id)
      {:ok, sheet} = Systems.character(bundle, %{"traits" => [trait]})
      {:ok, actor} = Systems.actor(bundle, sheet, "mara", "Mara")
      base = SceneFixtures.scene()
      actors = Map.values(Map.put(base.actors, "mara", actor))
      state = SceneFixtures.scene(Map.put(Systems.scene_rules(bundle), :actors, actors))

      assert {:ok, next, [effect]} =
               Scene.reduce(
                 state,
                 "mara",
                 %{type: "access", target_id: "moll"},
                 SceneFixtures.inputs(state, id)
               )

      assert effect.result["cost"] == cost
      assert next.actors["mara"].resources["effort"] == 10 - cost
      assert next.rules_ref == bundle.ref
    end
  end

  test "pool attributes add dice through the same check path, with no unused or unrecorded draws" do
    {:ok, original} = Systems.load("fantasy_demo")
    data = original.data

    data =
      put_in(data["actions"]["attempt"]["check"], %{
        "mode" => "pool",
        "count" => 1,
        "sides" => 6,
        "success_at" => 5,
        "target" => 1
      })

    {:ok, bundle} = Bundle.validate(data)
    {:ok, sheet} = Systems.character(bundle)

    assert {:ok, _, %{total: 1, draws: [1, 2, 5]}} =
             Declarative.resolve(bundle, sheet, "attempt", [1, 2, 5])

    assert {:error, :invalid_draws} = Declarative.resolve(bundle, sheet, "attempt", [5])
    {:ok, actor} = Systems.actor(bundle, sheet, "mara", "Mara")
    base = SceneFixtures.scene()

    state =
      SceneFixtures.scene(
        Map.put(
          Systems.scene_rules(bundle),
          :actors,
          Map.values(Map.put(base.actors, "mara", actor))
        )
      )

    inputs = %{SceneFixtures.inputs(state, "pool") | draws: [1, 2, 5]}

    assert {:ok, _, [effect]} =
             Scene.reduce(state, "mara", %{type: "attempt", target_id: "moll"}, inputs)

    assert effect.resolution.total == 1
    assert effect.draws == [1, 2, 5]
  end
end
