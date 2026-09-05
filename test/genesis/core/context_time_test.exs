defmodule Genesis.Core.ContextTimeTest do
  use ExUnit.Case, async: true
  import Genesis.SceneFixtures
  alias Genesis.Core.{Compound, Context, FictionalTime, Scene, Scope, State}

  test "deeds, traits and present companions independently change mechanics; beliefs do not" do
    state = scene()
    assert access(state)["outcome"] == "confrontation"
    assert access(state)["cost"] == 2
    origin = put_in(state.actors["mara"].traits, ["riverborn"])
    assert access(origin)["cost"] == 1
    irrelevant = put_in(state.actors["mara"].traits, ["left-handed"])
    assert access(irrelevant) == access(state)

    assert {:ok, helped, [event]} =
             Scene.reduce(
               state,
               "mara",
               %{type: "help", target_id: "moll"},
               inputs(state, "rescue")
             )

    assert helped.knowledge["rescue/fact"].source_ids == [event.id]
    assert access(helped)["outcome"] == "admitted"
    assert helped.elapsed == 60
    assert helped.actors["mara"].resources["effort"] == 9

    assert {:ok, later, _} =
             Scene.reduce(
               helped,
               "mara",
               %{type: "take", target_id: "ration"},
               inputs(helped, "after-rescue")
             )

    assert access(later)["outcome"] == "admitted"
    companion = put_in(state.actors["reed"].companion_of, "mara")
    assert access(companion)["outcome"] == "admitted"
    assert access(put_in(companion.actors["reed"].alive, false))["outcome"] == "confrontation"
    hostile = put_in(companion.knowledge["friendship"].value, "hostile")
    assert access(hostile)["outcome"] == "confrontation"
    private_deed = put_in(helped.knowledge["rescue/fact"].audience, {:actors, ["mara"]})
    assert access(private_deed)["outcome"] == "confrontation"
  end

  test "proposals clarify without mutation, bind all terms, and reject stale or altered confirmation" do
    state = scene()
    assert {:clarify, :target_id} = Scene.propose(state, "mara", %{type: "access"}, "proposal")

    assert {:ok, proposal} =
             Scene.propose(state, "mara", %{type: "access", target_id: "moll"}, "proposal")

    refute Map.has_key?(Scene.proposal_view(proposal).terms, :sources)
    assert {:ok, next, [event]} = Scene.confirm(state, proposal, inputs(state, "access-1"))
    assert event.result == %{"outcome" => "confrontation", "cost" => 2}
    assert next.actors["mara"].resources["effort"] == 8
    assert {:error, :stale_proposal} = Scene.confirm(next, proposal, inputs(next, "access-2"))
    tampered = %{proposal | terms: Map.put(proposal.terms, "cost", 0)}
    assert {:error, :stale_proposal} = Scene.confirm(state, tampered, inputs(state, "tamper"))
    changed_companion = put_in(state.actors["reed"].companion_of, "mara")

    assert {:error, :stale_proposal} =
             Scene.confirm(
               changed_companion,
               proposal,
               inputs(changed_companion, "stale-context")
             )
  end

  test "a compound distraction then invalid take keeps the first cost, deed and time" do
    state = scene()

    steps = [
      {%{type: "distract", target_id: "moll"}, inputs(state, "plan/0")},
      {%{type: "take", target_id: "sealed-letter"}, inputs(state, "plan/1")}
    ]

    assert {:partial, next, [effect], 1, :unavailable} = Compound.run(state, "mara", steps)
    assert effect.id == "plan/0"
    assert next.actors["mara"].resources["effort"] == 9
    assert next.elapsed == 10
    assert next.knowledge["plan/0/fact"].value
    assert next.items == state.items
  end

  test "scope and calendar are explicit; pause, zero duration and published values do not drift" do
    state = scene()
    paused = State.pause(state)
    assert paused.time == state.time
    assert State.resume(paused).elapsed == 0
    assert State.pause(paused) == paused

    assert {:error, :paused} =
             Scene.reduce(
               paused,
               "mara",
               %{type: "take", target_id: "ration"},
               inputs(paused, "paused")
             )

    assert {:ok, same} = FictionalTime.advance(state.time, %{unit: :second, value: 0})
    assert same == state.time
    assert {:ok, :eq} = FictionalTime.compare(same, state.time)

    for other <- [
          %{same | world_id: "elsewhere"},
          %{same | calendar_version: 2},
          %{same | calendar_id: "earth"}
        ] do
      assert {:error, :incompatible_time} = FictionalTime.compare(same, other)
    end

    for duration <- [
          %{unit: :month, value: 1},
          %{unit: :second, value: -1},
          %{unit: :second, value: 1.5}
        ] do
      assert {:error, :unsupported_duration} = FictionalTime.advance(same, duration)
    end

    {:ok, published_scope} = Scope.new(%{world_id: "ashfall", generation: 0, kind: :published})
    published = %{state | scope: published_scope}

    assert {:error, :read_only_scope} =
             Scene.reduce(
               published,
               "mara",
               %{type: "take", target_id: "ration"},
               inputs(published, "published")
             )

    assert {:error, :wrong_scope} =
             Scene.reduce(
               state,
               "mara",
               %{type: "take", target_id: "ration"},
               inputs(published, "wrong")
             )

    assert {:ok, _, _} =
             Scene.reduce(
               state,
               "mara",
               %{type: "help", target_id: "moll"},
               inputs(state, "local")
             )

    assert published.time == state.time
  end

  test "historical public effects have a fixed audience; new membership does not reveal them" do
    state = scene()

    {:ok, _, effects} =
      Scene.reduce(state, "mara", %{type: "help", target_id: "moll"}, inputs(state, "witnessed"))

    assert [%{id: "witnessed"}] = Scene.effects_for(effects, %{actor_id: "courier"})
    assert [] = Scene.effects_for(effects, %{actor_id: "newcomer"})

    assert Enum.all?(
             Scene.effects_for(effects, %{actor_id: "courier"}),
             &(not Map.has_key?(&1, :source_ids))
           )
  end

  defp access(state), do: Context.resolve(state, "mara", "moll", state.actions["access"])
end
