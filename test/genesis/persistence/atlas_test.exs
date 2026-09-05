defmodule Genesis.Persistence.AtlasTest do
  use Genesis.DataCase, async: false
  alias Genesis.Accounts.Scope, as: UserScope
  alias Genesis.{Campaigns, Content, Worlds}
  alias Genesis.Content.{Atlas, AtlasEntry}
  alias Genesis.Persistence.{Codec, Draft, Event, Outbox, Snapshot}
  import Genesis.AccountsFixtures
  alias Genesis.Engine.WorldSupervisor
  import Genesis.WorldFixtures

  setup do
    ctx = world_fixture()

    start_supervised!(
      {WorldSupervisor,
       registry: Genesis.Engine.Registry,
       world_id: ctx.world.id,
       generation: ctx.world.generation,
       owner: self(),
       storage: :postgres,
       observer: self()}
    )

    assert_receive {:genesis_world_started, _world}

    {:ok, ctx}
  end

  test "a linked region is a durable World command with an idempotent receipt", ctx do
    attrs = %{
      "kind" => "region",
      "name" => "Ashfall Reach",
      "body" => "The river basin",
      "visibility" => "public"
    }

    assert {:ok, %{"status" => "published"} = result} =
             Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "reach")

    assert {:ok, ^result} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "reach")
    assert Repo.aggregate(AtlasEntry, :count) == 1
    assert Repo.get!(AtlasEntry, result["entity_id"]).data["version"] == 1

    assert {:error, :request_conflict} =
             Atlas.save(ctx.owner, ctx.world.id, nil, 0, %{attrs | "name" => "Other"}, "reach")

    event = Repo.one!(from e in Event, where: like(e.scope_key, "atlas:%"))
    assert {:ok, %{"after" => after_data, type: "atlas_record_saved"}} = Codec.load(event.event)
    assert after_data["name"] == "Ashfall Reach"
    assert Repo.get_by!(Outbox, event_id: event.id)
    assert_enqueued(worker: Genesis.Persistence.DeliverEvent)
  end

  test "runtime bindings read through renames and invisible links never enter search or counts",
       ctx do
    attrs = relation("Secret membership", "actor:moll", "item:sealed-letter")
    assert {:ok, _} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "secret-link")
    assert {:ok, %{count: 1}} = Atlas.search(ctx.owner, ctx.world.id, "Secret membership")

    assert {:ok, %{count: 0, records: [], more: false}} =
             Atlas.search(ctx.owner, ctx.world.id, "Secret membership", public: true)

    assert {:ok, %{links: []}} = Atlas.get(ctx.owner, ctx.world.id, "actor:moll", public: true)

    assert {:error, :unavailable} =
             Atlas.get(ctx.owner, ctx.world.id, "item:sealed-letter", public: true)

    assert {:ok, _} =
             Atlas.save(
               ctx.owner,
               ctx.world.id,
               nil,
               0,
               relation("A public connection", "actor:moll", "zone:bridge"),
               "public-link"
             )

    assert {:ok, %{links: [link]}} =
             Atlas.get(ctx.owner, ctx.world.id, "actor:moll", public: true)

    assert link.name == "A public connection"

    assert {:ok, _} =
             Content.curate(
               ctx.owner,
               ctx.world.id,
               "bridge",
               0,
               "moll",
               %{"kind" => "npc", "name" => "Moll Vale"},
               "rename"
             )

    assert {:ok, %{record: %{name: "Moll Vale", editable: false}}} =
             Atlas.get(ctx.owner, ctx.world.id, "actor:moll")

    assert {:ok, %{count: 1}} = Atlas.search(ctx.owner, ctx.world.id, "Moll Vale", public: true)

    assert {:error, :invalid_record} =
             Atlas.save(
               ctx.owner,
               ctx.world.id,
               nil,
               0,
               %{"kind" => "actor", "name" => "Copy"},
               "copy"
             )
  end

  test "stale saves, archival tombstones, and window drafts preserve the published base", ctx do
    attrs = %{"kind" => "region", "name" => "Reach", "visibility" => "public"}
    assert {:ok, result} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "region")
    id = result["entity_id"]

    child = %{
      "kind" => "location",
      "name" => "Village",
      "parent" => "record:" <> id,
      "visibility" => "public"
    }

    assert {:ok, child_result} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, child, "village")

    assert {:error, :location_cycle} =
             Atlas.save(
               ctx.owner,
               ctx.world.id,
               id,
               1,
               Map.put(attrs, "parent", "record:" <> child_result["entity_id"]),
               "cycle"
             )

    assert {:ok, _} =
             Atlas.save(
               ctx.owner,
               ctx.world.id,
               id,
               1,
               Map.put(attrs, "archived", true),
               "archive"
             )

    assert {:error, :stale_revision} = Atlas.save(ctx.owner, ctx.world.id, id, 1, attrs, "stale")
    assert {:ok, %{count: 0}} = Atlas.search(ctx.owner, ctx.world.id, "Reach", public: true)

    assert {:ok, %{record: %{archived: true}}} =
             Atlas.get(ctx.owner, ctx.world.id, "record:" <> id, archived: true)

    assert {:ok, %{record: %{parent: nil}}} =
             Atlas.get(ctx.owner, ctx.world.id, "record:" <> child_result["entity_id"],
               public: true
             )

    assert {:error, :invalid_reference} =
             Atlas.save(ctx.owner, ctx.world.id, nil, 0, child, "dangling")

    row = Repo.get!(AtlasEntry, child_result["entity_id"])
    assert row.data["parent"] == "record:" <> id

    ctx = experience_fixture(ctx)

    assert {:ok, %{"status" => "draft"}} =
             Atlas.save(
               ctx.owner,
               ctx.world.id,
               row.id,
               row.revision,
               %{child | "name" => "Future village", "parent" => nil},
               "draft"
             )

    assert Repo.get!(AtlasEntry, row.id) == row
    assert Repo.get!(Snapshot, ctx.snapshot.id).digest == ctx.snapshot.digest
    assert Repo.get_by!(Draft, kind: "atlas").zone_id == "@atlas"
    assert {:ok, %{count: 0}} = Atlas.search(ctx.owner, ctx.world.id, "Future village")
  end

  test "campaign privacy and revocation filter titles, bodies, tags and returned links before pagination",
       ctx do
    player = UserScope.for_user(user_fixture())
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, player.user.id, "viewer", "viewer")

    {:ok, other} =
      Campaigns.create_campaign(ctx.owner, ctx.world.id, %{"name" => "Courier"}, "courier")

    {:ok, _} =
      Campaigns.add_member(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        player.user.id,
        "player",
        "member"
      )

    attrs = %{
      "kind" => "article",
      "name" => "Private destination",
      "body" => "Needle in the body",
      "tags" => ["secret-tag"],
      "visibility" => "party",
      "campaign_id" => other.id
    }

    assert {:ok, _} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "secret")

    for query <- ["Private destination", "Needle", "secret-tag"] do
      assert {:ok, %{records: [], count: 0}} = Atlas.search(player, ctx.world.id, query)
    end

    own = %{attrs | "campaign_id" => ctx.campaign.id, "name" => "Dock plans"}
    assert {:ok, _} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, own, "own")
    assert {:ok, %{count: 1}} = Atlas.search(player, ctx.world.id, "Dock plans")

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        player.user.id,
        "mara",
        "bind"
      )

    ctx = experience_fixture(ctx)

    assert {:ok, page} =
             Atlas.player_search(player, ctx.world.id, ctx.experience.id, "mara", "plans")

    assert page.count == 1
    assert page.scope.kind == :experience

    assert {:error, :unavailable} =
             Atlas.player_search(player, ctx.world.id, ctx.experience.id, "moll")

    {:ok, _} =
      Campaigns.revoke_member(ctx.owner, ctx.world.id, ctx.campaign.id, player.user.id, "revoke")

    assert {:ok, %{count: 0}} = Atlas.search(player, ctx.world.id, "Dock plans")

    assert {:error, :unavailable} =
             Atlas.player_search(player, ctx.world.id, ctx.experience.id, "mara")

    assert {:error, :unauthorized} = Atlas.save(player, ctx.world.id, nil, 0, own, "forged")
  end

  test "campaign drafts are not leaked by the general workspace draft list", ctx do
    builder = UserScope.for_user(user_fixture())
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "builder", "builder")
    _ctx = experience_fixture(ctx)

    attrs = %{
      "kind" => "article",
      "name" => "Private campaign future",
      "body" => "Secret",
      "visibility" => "party",
      "campaign_id" => ctx.campaign.id
    }

    assert {:ok, %{"status" => "draft"}} =
             Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "private-draft")

    assert [%{kind: "atlas"}] = Content.list_drafts(ctx.owner, ctx.world.id)
    assert Content.list_drafts(builder, ctx.world.id) == []
  end

  test "World restart recovers the atlas and its receipt without another event", ctx do
    attrs = %{"kind" => "article", "name" => "A lasting chronicle"}
    assert {:ok, result} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "chronicle")
    count = Repo.aggregate(Event, :count)

    world =
      GenServer.whereis(
        Genesis.Engine.Supervisor.via(Genesis.Engine.Registry, {:world, ctx.world.id})
      )

    monitor = Process.monitor(world)
    :ok = GenServer.stop(world, :normal)
    assert_receive {:DOWN, ^monitor, :process, ^world, :normal}
    assert_receive {:genesis_world_started, new_world}
    refute new_world == world
    assert {:ok, ^result} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "chronicle")
    assert Repo.aggregate(Event, :count) == count
    assert {:ok, %{count: 1}} = Atlas.search(ctx.owner, ctx.world.id, "lasting")
  end

  test "two stale authors serialize at the existing owner and only one revision wins", ctx do
    attrs = %{"kind" => "article", "name" => "Original"}
    {:ok, result} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "original")
    supervisor = start_supervised!({Task.Supervisor, []})

    tasks =
      for name <- ~w(First Second) do
        Task.Supervisor.async(supervisor, fn ->
          Atlas.save(
            ctx.owner,
            ctx.world.id,
            result["entity_id"],
            1,
            %{attrs | "name" => name},
            name
          )
        end)
      end

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, %{"revision" => 2}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :stale_revision})) == 1
    assert Repo.get!(AtlasEntry, result["entity_id"]).revision == 2
  end

  test "hidden matches cannot consume the first page or reveal totals", ctx do
    for number <- 1..51 do
      assert {:ok, _} =
               Atlas.save(
                 ctx.owner,
                 ctx.world.id,
                 nil,
                 0,
                 %{"kind" => "article", "name" => "Index #{number}"},
                 "index-#{number}"
               )
    end

    assert {:ok, _} =
             Atlas.save(
               ctx.owner,
               ctx.world.id,
               nil,
               0,
               %{"kind" => "article", "name" => "Index visible", "visibility" => "public"},
               "visible"
             )

    assert {:ok, %{count: 52, more: true, records: records}} =
             Atlas.search(ctx.owner, ctx.world.id, "Index")

    assert length(records) == 50

    assert {:ok, %{count: 1, more: false, records: [visible]}} =
             Atlas.search(ctx.owner, ctx.world.id, "Index", public: true)

    assert visible.name == "Index visible"
  end

  defp relation(name, source, target),
    do: %{
      "kind" => "relationship",
      "name" => name,
      "source" => source,
      "target" => target,
      "relation" => "documents",
      "visibility" => "public"
    }
end
