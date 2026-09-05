defmodule Genesis.SettlementFixtures do
  @moduledoc false
  alias Genesis.Core.{Curation, Scene}
  alias Genesis.{SceneFixtures, Systems}

  def scene(opts \\ []) do
    {:ok, bundle} = Systems.load(Keyword.get(opts, :ruleset, "fantasy_local"))
    scene(Systems.scene_rules(bundle), opts)
  end

  def scene(rules, opts) do
    state = SceneFixtures.scene(rules)

    state =
      Enum.reduce(["moll", "reed"], state, fn id, state ->
        {:ok, state} =
          Curation.apply(state, id, %{"kind" => "npc", "name" => state.actors[id].name})

        state
      end)

    {:ok, state} = Curation.apply(state, "settlement", configuration(opts))

    currency =
      if Keyword.get(opts, :profile, "temple_market") == "temple_market",
        do: [{"mara", "coin", 100}, {"courier", "coin", 100}, {"moll", "coin", 200}],
        else: []

    holdings =
      currency ++
        [
          {"moll", "grain", Keyword.get(opts, :merchant_stock, 12)},
          {"mara", "grain", 2},
          {"mara", "ration", 3},
          {"courier", "ration", 2},
          {"reed", "grain", 4}
        ]

    Enum.reduce(holdings, state, fn {owner, commodity, amount}, state ->
      {:ok, state} =
        Curation.apply(state, owner <> "-" <> commodity, %{
          "kind" => "stock",
          "name" => commodity,
          "commodity" => commodity,
          "quantity" => amount,
          "owner_id" => owner,
          "reason" => "Authored opening holdings"
        })

      state
    end)
  end

  def configuration(opts \\ []),
    do: %{
      "kind" => "settlement",
      "name" => "Ashfall relief market",
      "profile" => Keyword.get(opts, :profile, "temple_market"),
      "merchant_id" => "moll",
      "representative_id" => "reed",
      "tradition" => "Keep a place at the table",
      "claim" => "Adherents believe the lantern watches over travelers",
      "witnessing" => Keyword.get(opts, :witnessing, true)
    }

  def action(state, actor, type, target, id, extras \\ %{}) do
    intent = Map.merge(%{type: type, target_id: target}, extras)
    Scene.reduce(state, actor, intent, SceneFixtures.inputs(state, id))
  end
end
