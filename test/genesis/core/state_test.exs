defmodule Genesis.Core.StateTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Actor, FictionalTime, Item, Scope, State}

  test "a scoped scene validates unique ownership without creating processes" do
    {:ok, scope} =
      Scope.new(%{
        world_id: "ashfall",
        generation: 0,
        kind: :experience,
        window_id: "window-1",
        id: "dock-crew"
      })

    {:ok, time} = FictionalTime.new("ashfall", "village", 1, 8_640_000)

    attrs = %{
      scope: scope,
      zone_id: "bridge",
      time: time,
      actors: [%Actor{id: "mara", name: "Mara", kind: :pc}],
      items: [%Item{id: "ration", name: "Ration", owner: {:zone, "bridge"}}]
    }

    assert {:ok, state} = State.new(attrs)
    assert state.items["ration"].owner == {:zone, "bridge"}
    assert state.actors["mara"].name == "Mara"
    assert {:error, :invalid_state} = State.new(%{attrs | actors: attrs.actors ++ attrs.actors})

    assert {:error, :invalid_state} =
             State.new(%{attrs | items: [%{hd(attrs.items) | owner: {:actor, "absent"}}]})
  end

  test "invalid identities, executable configuration and malformed contexts are rejected at construction" do
    for attrs <- [
          %{},
          %{world_id: "world", generation: -1, kind: :published},
          %{world_id: "world", generation: 0, kind: :experience},
          %{world_id: "world", generation: 0, kind: :published, id: "other"},
          %{world_id: :world, generation: 0, kind: :published}
        ] do
      assert {:error, :invalid_scope} = Scope.new(attrs)
    end

    state = Genesis.SceneFixtures.scene()
    attrs = %{scope: state.scope, zone_id: state.zone_id, time: state.time}

    for changes <- [
          %{rules_ref: fn -> :unsafe end},
          %{actions: %{"take" => %{}}},
          %{context_rules: [nil]},
          %{
            context_rules: [
              %{
                "id" => "bad",
                "priority" => 1,
                "when" => %{"kind" => "eval", "key" => "code"},
                "set" => %{"cost" => 1}
              }
            ]
          }
        ] do
      assert {:error, :invalid_state} = State.new(Map.merge(attrs, changes))
    end
  end

  test "knowledge kinds stay distinct and sources never become disclosed by a private memory" do
    state = Genesis.SceneFixtures.scene()

    records =
      for {kind, index} <-
            Enum.with_index([:observation, :belief, :relationship, :obligation, :memory]) do
        %{
          state.knowledge["rumor"]
          | id: "record-#{index}",
            kind: kind,
            source_ids: ["secret-source"]
        }
      end

    attrs = %{
      scope: state.scope,
      zone_id: state.zone_id,
      time: state.time,
      actors: Map.values(state.actors),
      knowledge: records
    }

    assert {:ok, typed} = State.new(attrs)
    {:ok, view} = State.view(typed, %{actor_id: "mara", role: :player})

    assert Enum.map(view.knowledge, & &1.kind) == [
             :observation,
             :belief,
             :relationship,
             :obligation,
             :memory
           ]

    refute inspect(view) =~ "secret-source"
    {:ok, other} = State.view(typed, %{actor_id: "courier", role: :player})
    assert other.knowledge == []
    bad = %{hd(records) | scope: %{state.scope | id: "other-experience"}}
    assert {:error, :invalid_state} = State.new(%{attrs | knowledge: [bad]})
  end
end
