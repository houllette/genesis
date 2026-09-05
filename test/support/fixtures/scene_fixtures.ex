defmodule Genesis.SceneFixtures do
  @moduledoc false
  alias Genesis.Core.{Actor, FictionalTime, Item, Knowledge, Scope, State}

  def scene(attrs \\ %{}) do
    {:ok, scope} =
      Scope.new(%{
        world_id: "ashfall",
        generation: 0,
        kind: :experience,
        window_id: "window-1",
        id: "dock-crew"
      })

    {:ok, time} = FictionalTime.new("ashfall", "village", 1, 8_640_000)

    actors = [
      %Actor{id: "mara", name: "Mara", kind: :pc, resources: %{"effort" => 10}},
      %Actor{id: "courier", name: "Courier", kind: :pc, resources: %{"effort" => 10}},
      %Actor{id: "moll", name: "Moll", kind: :npc},
      %Actor{id: "reed", name: "Reed", kind: :npc, skills: %{"diplomacy" => 1}}
    ]

    knowledge = [
      %Knowledge{
        id: "secret",
        kind: :fact,
        subject_id: "moll",
        predicate: "hiding",
        value: "cellar",
        scope: scope,
        source_ids: ["authored-secret"],
        occurred_at: time.value,
        audience: :gm
      },
      %Knowledge{
        id: "rumor",
        kind: :belief,
        subject_id: "mara",
        predicate: "helped",
        value: true,
        scope: scope,
        source_ids: ["heard-rumor"],
        occurred_at: time.value,
        learned_at: time.value,
        audience: {:actors, ["mara"]}
      },
      %Knowledge{
        id: "friendship",
        kind: :relationship,
        subject_id: "moll",
        object_id: "reed",
        predicate: "standing",
        value: "allied",
        scope: scope,
        source_ids: ["prior-friendship"],
        occurred_at: time.value,
        audience: {:actors, ["moll", "reed"]}
      }
    ]

    defaults = %{
      scope: scope,
      zone_id: "bridge",
      time: time,
      actors: actors,
      knowledge: knowledge,
      items: [
        %Item{id: "ration", name: "Ration", owner: {:zone, "bridge"}, quantity: 2},
        %Item{id: "sealed-letter", name: "Secret letter", owner: {:zone, "bridge"}, audience: :gm}
      ],
      rules_ref: {"scene", 1},
      actions: actions(),
      context_rules: context_rules()
    }

    {:ok, state} = State.new(Map.merge(defaults, attrs))
    state
  end

  def inputs(state, id),
    do: %{
      scope: state.scope,
      expected_revision: state.revision,
      event_id: id,
      recorded_at: ~U[2026-09-04 12:00:00.123456Z],
      draws: []
    }

  def actions do
    %{
      "take" => %{"kind" => "take", "duration" => 0, "cost" => 0, "resource" => "effort"},
      "help" => %{
        "kind" => "deed",
        "duration" => 60,
        "cost" => 1,
        "resource" => "effort",
        "fact" => "helped"
      },
      "distract" => %{
        "kind" => "deed",
        "duration" => 10,
        "cost" => 1,
        "resource" => "effort",
        "fact" => "distracted"
      },
      "access" => %{
        "kind" => "access",
        "duration" => 0,
        "cost" => 2,
        "resource" => "effort",
        "outcome" => "confrontation"
      }
    }
  end

  def context_rules do
    [
      %{
        "id" => "origin-discount",
        "priority" => 10,
        "when" => %{"kind" => "trait", "key" => "riverborn"},
        "set" => %{"cost" => 1}
      },
      %{
        "id" => "rescuer",
        "priority" => 20,
        "when" => %{"kind" => "deed", "key" => "helped"},
        "set" => %{"outcome" => "admitted"}
      },
      %{
        "id" => "companion-ally",
        "priority" => 30,
        "when" => %{"kind" => "companion", "key" => "diplomacy", "relationship" => "allied"},
        "set" => %{"outcome" => "admitted"}
      },
      %{
        "id" => "companion-enemy",
        "priority" => 40,
        "when" => %{"kind" => "companion", "key" => "diplomacy", "relationship" => "hostile"},
        "set" => %{"outcome" => "confrontation"}
      }
    ]
  end
end
