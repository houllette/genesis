defmodule Genesis.Core.CompanionsTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Context, Scene, State, Transfer}
  import Genesis.SceneFixtures

  test "an invitation is not control; refusal is durable and costs no inventory" do
    state = scene()
    assert {:ok, invited, [_]} = act(state, "recruit", "reed", "invite")
    assert invited.actors["reed"].companion_of == nil
    assert {:ok, refused, [event]} = act(invited, "agree", "reed", "answer")
    assert event.result["outcome"] == "refused"
    assert refused.actors["reed"].companion_of == nil
    assert refused.items == state.items
    assert {:ok, ^refused} = State.restore(refused)
  end

  test "a voluntary companion and its inventory travel as one bounded party, retaining relationships" do
    state = scene()

    state =
      put_in(
        state.actors["reed"],
        Map.put(state.actors["reed"], :companion_policy, %{
          "version" => 1,
          "willing" => true,
          "max_trips" => 1
        })
      )

    assert {:ok, invited, [_]} = act(state, "recruit", "reed", "invite")
    assert {:ok, following, [_]} = act(invited, "agree", "reed", "answer")
    assert following.actors["reed"].companion_of == "mara"
    destination = %{state | zone_id: "docks", actors: %{}, items: %{}, knowledge: %{}}
    assert {:ok, left, right} = Transfer.move(following, destination, "mara")
    refute Map.has_key?(left.actors, "reed")
    assert right.actors["reed"].id == "reed"
    assert right.actors["reed"].companion_of == nil
    assert left.knowledge["friendship"] == state.knowledge["friendship"]

    assert Enum.sort(Map.keys(left.items) ++ Map.keys(right.items)) ==
             Enum.sort(Map.keys(state.items))

    assert {:ok, ^left} = State.restore(left)
    assert {:ok, ^right} = State.restore(right)
    assert {:ok, journal} = State.view(right, %{role: :gm})
    assert Enum.any?(journal.knowledge, &(&1.predicate == "companionship"))
  end

  test "departure removes present benefits, not relationship history; hostile context differs" do
    state = scene()

    state =
      put_in(state.actors["reed"].companion_policy, %{
        "version" => 1,
        "willing" => true,
        "max_trips" => 2
      })

    {:ok, state, _} = act(state, "recruit", "reed", "invite")
    {:ok, state, _} = act(state, "agree", "reed", "agree")
    defaults = %{"cost" => 5, "outcome" => "confrontation"}
    allied = Context.resolve(state, "mara", "moll", defaults)
    hostile = put_in(state.knowledge["friendship"].value, "hostile")
    hostile = Context.resolve(hostile, "mara", "moll", defaults)
    assert allied["outcome"] == "admitted"
    assert hostile["outcome"] == "confrontation"
    assert "friendship" in allied.sources
    {:ok, dismissed, _} = act(state, "dismiss", "reed", "dismiss")
    assert dismissed.knowledge["friendship"] == state.knowledge["friendship"]
    assert Context.resolve(dismissed, "mara", "moll", defaults)["outcome"] == "confrontation"
    dead = put_in(state.actors["reed"].alive, false)
    assert Context.resolve(dead, "mara", "moll", defaults)["outcome"] == "confrontation"
    destination = %{state | zone_id: "docks", actors: %{}, items: %{}, knowledge: %{}}
    assert {:error, :companion_unavailable} = Transfer.move(dead, destination, "mara")
    assert {:ok, _, _} = act(dead, "dismiss", "reed", "release-dead")
  end

  test "another PC cannot agree to someone else's invitation or control the follower" do
    state = scene()
    {:ok, state, _} = act(state, "recruit", "reed", "invite")

    assert {:error, :invitation_required} =
             Scene.propose(state, "courier", %{type: "agree", target_id: "reed"}, "steal")

    assert {:error, :invitation_pending} =
             Scene.propose(state, "courier", %{type: "recruit", target_id: "reed"}, "compete")
  end

  test "taking and dropping an ordinary item conserves identity and cannot drop another actor's goods" do
    state = scene()
    {:ok, taken, _} = act(state, "take", "ration", "take")

    assert {:error, :unavailable} =
             Scene.propose(taken, "courier", %{type: "drop", target_id: "ration"}, "steal")

    {:ok, dropped, _} = act(taken, "drop", "ration", "drop")
    assert dropped.items == state.items
    assert dropped.elapsed == taken.elapsed
  end

  defp act(state, type, target, id) do
    Scene.reduce(state, "mara", %{type: type, target_id: target}, %{
      scope: state.scope,
      expected_revision: state.revision,
      event_id: id,
      draws: []
    })
  end
end
