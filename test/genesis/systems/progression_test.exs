defmodule Genesis.Core.ProgressionTest do
  use ExUnit.Case, async: true
  import Genesis.SceneFixtures
  alias Genesis.Core.{Progression, Scene}
  alias Genesis.Systems

  test "each bundle grants one sourced social award; reopening cannot farm it" do
    for id <- ["fantasy_demo", "cyberpunk_demo"] do
      {:ok, bundle} = Systems.load(id)
      policy = bundle.data["progression"]
      state = scene(Systems.scene_rules(bundle))

      assert {:error, :ineligible_award} =
               Progression.award(state, "mara", policy, inputs(state, "award"))

      {:ok, helped, _} =
        Scene.reduce(state, "mara", %{type: "help", target_id: "moll"}, inputs(state, "rescue"))

      assert {:ok, awarded, [effect]} =
               Progression.award(helped, "mara", policy, inputs(helped, "award"))

      assert effect.result["outcome"] == "village-access"
      assert effect.source_ids == ["rescue/fact"]
      assert awarded.knowledge["award/fact"].source_ids == ["award"]
      assert awarded.knowledge["award/fact"].predicate == "award:bridge-service"

      assert {:error, :ineligible_award} =
               Progression.award(awarded, "mara", policy, inputs(awarded, "new-request"))

      assert awarded.elapsed == 60
    end
  end

  test "defeat is nonlethal unless prior consent matches actor, scope, policy and revision" do
    for id <- ["fantasy_demo", "cyberpunk_demo"] do
      {:ok, bundle} = Systems.load(id)
      state = scene(Systems.scene_rules(bundle))
      policy = bundle.data["progression"]
      {:ok, injured, _} = Progression.defeat(state, "mara", policy, nil, inputs(state, "defeat"))
      assert injured.actors["mara"].alive
      assert injured.knowledge["defeat/fact"].value == "injured"

      consent = %{
        actor_id: "mara",
        scope: state.scope,
        policy_version: 1,
        risk: "permadeath",
        accepted: true,
        revision: 0
      }

      {:ok, dead, _} = Progression.defeat(state, "mara", policy, consent, inputs(state, "defeat"))
      refute dead.actors["mara"].alive

      for invalid <- [
            %{consent | actor_id: "courier"},
            %{consent | policy_version: 2},
            %{consent | accepted: false},
            %{consent | revision: 99}
          ] do
        {:ok, safe, _} =
          Progression.defeat(state, "mara", policy, invalid, inputs(state, "defeat"))

        assert safe.actors["mara"].alive
      end
    end
  end

  test "retirement transfers the selected asset once and leaves private knowledge with its original actor" do
    for id <- ["fantasy_demo", "cyberpunk_demo"] do
      {:ok, bundle} = Systems.load(id)
      state = scene(Systems.scene_rules(bundle))

      {:ok, holding, _} =
        Scene.reduce(state, "mara", %{type: "take", target_id: "ration"}, inputs(state, "take"))

      assert {:error, :invalid_transfer} =
               Progression.retire(
                 holding,
                 "mara",
                 "courier",
                 ["ration", "ration"],
                 inputs(holding, "retire")
               )

      assert {:ok, retired, _} =
               Progression.retire(
                 holding,
                 "mara",
                 "courier",
                 ["ration"],
                 inputs(holding, "retire")
               )

      assert retired.actors["mara"].retired
      assert retired.items["ration"].owner == {:actor, "courier"}
      assert retired.items["ration"].quantity == 2
      assert retired.knowledge["rumor"] == state.knowledge["rumor"]

      assert {:error, :unavailable} =
               Progression.retire(retired, "mara", "courier", [], inputs(retired, "again"))
    end
  end
end
