defmodule Genesis.Core.IncorporationTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Incorporation, Scene, State, Transfer}
  alias Genesis.Experiences
  import Genesis.SceneFixtures

  test "publication conserves relocated actors, holdings and private knowledge across the whole footprint" do
    {zones, original} = traveled()
    assert {:ok, [left, right]} = Incorporation.project_many(zones, %{})
    refute Map.has_key?(left.actors, "mara")
    refute Map.has_key?(left.items, "ration")
    refute Map.has_key?(left.knowledge, "rumor")
    assert right.actors["mara"] == original.actors["mara"]
    assert right.items["ration"] == original.items["ration"]
    assert right.knowledge["rumor"] == original.knowledge["rumor"]
    assert right.scope.kind == :published
    assert right.time == left.time and left.time == original.time
    assert {:ok, %{knowledge: []}} = State.view(right, %{role: :spectator, actor_id: nil})
    assert {:ok, ^left} = State.restore(left)
    assert {:ok, ^right} = State.restore(right)
  end

  test "a partial footprint, duplicate identity or silent loss cannot publish" do
    {[left, right], _} = traveled()
    assert {:error, :incorporation_conflict} = Incorporation.project_many([left], %{})

    assert {:error, :incorporation_conflict} =
             Incorporation.project_many([left, right, right], %{})

    lost = put_in(right.working.items, %{})
    assert {:error, :incorporation_conflict} = Incorporation.project_many([left, lost], %{})
    duplicate = put_in(left.working.actors["mara"], right.working.actors["mara"])
    assert {:error, :incorporation_conflict} = Incorporation.project_many([duplicate, right], %{})
  end

  test "base drift and unsupported metadata changes fail closed" do
    {[left, right], _} = traveled()
    drift = put_in(right.working.name, "silently renamed")
    assert {:error, :incorporation_conflict} = Incorporation.project_many([left, drift], %{})
    drift = put_in(left.working_base.actors["moll"].name, "different base")
    assert {:error, :incorporation_conflict} = Incorporation.project_many([drift, right], %{})
    assert {:error, :incorporation_conflict} = Incorporation.project_many([], %{})
  end

  test "malformed recorded events are rejected rather than crashing projection" do
    {[left, right], _} = traveled()
    left = put_in(left.working.events, [%{id: "malformed", scope: left.working.scope}])

    assert {:error, :incorporation_conflict} =
             Incorporation.project_many([left, right], %{"malformed" => "published-malformed"})
  end

  test "portable knowledge maps sources from another zone and incomplete mappings return an error" do
    base = scene()

    published =
      Experiences.rescope(base, %{base.scope | kind: :published, id: nil, window_id: nil})

    destination = %{base | zone_id: "docks", actors: %{}, items: %{}, knowledge: %{}}

    {:ok, acted, [event]} =
      Scene.reduce(base, "mara", %{type: "take", target_id: "ration"}, inputs(base, "take"))

    acted = put_in(acted.knowledge["rumor"].source_ids, [event.id])
    {:ok, left, right} = Transfer.move(acted, destination, "mara")

    zones = [
      %{published: published, working_base: base, working: left},
      %{
        published: Experiences.rescope(destination, published.scope),
        working_base: destination,
        working: right
      }
    ]

    assert {:error, :incorporation_conflict} = Incorporation.project_many(zones, %{})

    assert {:ok, [origin, arrived]} =
             Incorporation.project_many(zones, %{event.id => "published-take"})

    assert arrived.knowledge["rumor"].source_ids == ["published-take"]
    assert Enum.any?(origin.events, &(&1.id == "published-take" and &1.scope.kind == :published))
    assert arrived.events == []
  end

  defp traveled do
    working = put_in(scene().items["ration"].owner, {:actor, "mara"})
    published_scope = %{working.scope | kind: :published, id: nil, window_id: nil}
    published = Experiences.rescope(working, published_scope)
    destination = %{published | zone_id: "docks", actors: %{}, items: %{}, knowledge: %{}}
    base = Experiences.rescope(destination, working.scope)
    {:ok, left, right} = Transfer.move(working, base, "mara")

    {[
       %{published: published, working_base: working, working: left},
       %{published: destination, working_base: base, working: right}
     ], published}
  end
end
