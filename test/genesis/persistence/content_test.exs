defmodule Genesis.Persistence.ContentTest do
  use Genesis.DataCase, async: false
  alias Genesis.{Content, Experiences}
  alias Genesis.Engine.WorldSupervisor
  alias Genesis.Persistence.{Draft, Snapshot, Snapshots}
  import Genesis.WorldFixtures

  setup do
    ctx = world_fixture()

    start_supervised!(
      {WorldSupervisor,
       registry: Genesis.Engine.Registry,
       world_id: ctx.world.id,
       generation: ctx.world.generation,
       owner: self(),
       storage: :postgres}
    )

    {:ok, ctx}
  end

  test "authoring uses published authority, retries once and saves drafts during an open window",
       ctx do
    attrs = %{"kind" => "npc", "name" => "Edda"}

    assert {:ok, result} =
             Content.curate(ctx.owner, ctx.world.id, "bridge", 0, nil, attrs, "edda")

    assert result["status"] == "published"

    assert {:ok, ^result} =
             Content.curate(ctx.owner, ctx.world.id, "bridge", 0, nil, attrs, "edda")

    assert {:error, :stale_revision} =
             Content.curate(ctx.owner, ctx.world.id, "bridge", 0, nil, attrs, "stale")

    snapshot = Repo.get_by!(Snapshot, world_id: ctx.world.id, scope_kind: "published")
    assert {:ok, scene} = Snapshots.load(snapshot)
    assert map_size(scene.actors) == 5

    {:ok, exp} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "Night watch", "zone_id" => "bridge"},
        "night"
      )

    assert {:ok, _} = Experiences.start(ctx.owner, ctx.world.id, exp.id, 0)

    assert {:ok, %{"status" => "draft"}} =
             Content.curate(
               ctx.owner,
               ctx.world.id,
               "bridge",
               1,
               nil,
               %{"kind" => "npc", "name" => "Tess"},
               "tess"
             )

    assert Repo.aggregate(Draft, :count) == 1
    assert Repo.get!(Snapshot, snapshot.id).digest == snapshot.digest
  end

  test "linked notes require a real entity; private notes never enter public preview or engine facts",
       ctx do
    attrs = %{
      "entity_id" => "moll",
      "title" => "A suspicion",
      "body" => "Moll may leave",
      "kind" => "belief",
      "visibility" => "private"
    }

    assert {:ok, note} = Content.save_note(ctx.owner, ctx.world.id, nil, 0, attrs, "note")
    assert note.kind == "belief"
    assert {:ok, ^note} = Content.save_note(ctx.owner, ctx.world.id, nil, 0, attrs, "note")

    assert {:error, :invalid_note} =
             Content.save_note(
               ctx.owner,
               ctx.world.id,
               nil,
               0,
               %{attrs | "entity_id" => "missing"},
               "bad"
             )

    assert {:ok, public} = Content.preview(ctx.owner, ctx.world.id, "bridge")
    refute Enum.any?(public.knowledge, &(&1.value == "Moll may leave"))
    assert Content.list_notes(ctx.owner, ctx.world.id, public: true) == []

    assert {:ok, _hidden_link} =
             Content.save_note(
               ctx.owner,
               ctx.world.id,
               nil,
               0,
               %{attrs | "entity_id" => "sealed-letter", "visibility" => "public"},
               "hidden-link"
             )

    assert Content.list_notes(ctx.owner, ctx.world.id, public: true) == []
  end
end
