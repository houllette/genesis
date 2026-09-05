defmodule GenesisWeb.WorkspaceLiveTest do
  use GenesisWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Oban.Testing, only: [perform_job: 3]
  import Genesis.AccountsFixtures
  import Genesis.WorldFixtures
  alias Genesis.Accounts.Scope
  alias Genesis.{Campaigns, Content}
  alias Genesis.Engine.{Runtime, Session}
  alias Genesis.Engine.WorldSupervisor
  alias Genesis.Experiences
  alias Genesis.Persistence.{DeliverEvent, Outbox, Snapshot, Snapshots}
  alias Genesis.{Repo, Worlds}

  setup %{conn: conn} do
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

    assert_receive {:genesis_world_started, _pid}
    {:ok, Map.put(ctx, :conn, log_in_user(conn, ctx.owner.user))}
  end

  test "GM curates a place and a campaign, then pauses and reopens across gatherings without a player",
       ctx do
    {:ok, world, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}")

    {:ok, place, _} =
      world
      |> form("#new-zone-form", zone: %{name: "Lantern Quay", description: "A river landing."})
      |> render_submit()
      |> follow_redirect(ctx.conn)

    assert has_element?(place, "#place-title", "Lantern Quay")

    for name <- ["Edda", "Tess"] do
      place |> form("#record-form", record: %{name: name}) |> render_submit()
      assert has_element?(place, "#actors article", name)
    end

    place |> form("#record-form", record: %{kind: "item"}) |> render_change()

    place
    |> form("#record-form", record: %{name: "Brass lantern", quantity: "1"})
    |> render_submit()

    assert has_element?(place, "#items article", "Brass lantern")

    place
    |> form("#note-form",
      note: %{title: "A private plan", body: "Edda will ask about the ferry.", kind: "plan"}
    )
    |> render_submit()

    assert has_element?(place, "#notes article", "A private plan")
    place |> element("#preview-player") |> render_click()
    refute has_element?(place, "#notes article", "A private plan")
    refute has_element?(place, "#record-form")
    assert has_element?(place, "#actors article", "Edda")
    place |> element("#preview-player") |> render_click()

    place
    |> form("#note-form",
      note: %{title: "A public notice", body: "The ferry returns at dawn.", visibility: "public"}
    )
    |> render_submit()

    assert has_element?(place, "#notes article", "A public notice")

    zone = Enum.find(Content.list_zones(ctx.owner, ctx.world.id), &(&1.name == "Lantern Quay"))
    {:ok, world, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}")

    {:ok, campaign, _} =
      world
      |> form("#new-campaign-form", campaign: %{name: "River chronicles"})
      |> render_submit()
      |> follow_redirect(ctx.conn)

    {:ok, experience, _} =
      campaign
      |> form("#experience-form", experience: %{name: "First light", zone_id: zone.id})
      |> render_submit()
      |> follow_redirect(ctx.conn)

    assert has_element?(experience, "#start-experience")
    experience |> element("#start-experience") |> render_click()
    assert has_element?(experience, "#pause-experience")
    assert has_element?(experience, "#claims-held")

    experience
    |> form("#gathering-form", gathering: %{title: "Evening one", starts_at: "2026-09-12T18:00"})
    |> render_submit()

    assert has_element?(experience, "#gatherings article", "Evening one")
    experience |> element("#pause-experience") |> render_click()
    assert has_element?(experience, "#resume-experience")
    exp = Enum.find(Experiences.list(ctx.owner, ctx.world.id), &(&1.name == "First light"))
    {:ok, reopened, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{exp.id}")
    assert has_element?(reopened, "#resume-experience")
    assert has_element?(reopened, "#working-time", "0s")

    reopened
    |> form("#gathering-form", gathering: %{title: "Evening two", starts_at: "2026-10-01T18:00"})
    |> render_submit()

    assert has_element?(reopened, "#gatherings article", "Evening one")
    assert has_element?(reopened, "#gatherings article", "Evening two")
    reopened |> element("#resume-experience") |> render_click()
    assert has_element?(reopened, "#pause-experience")
    assert has_element?(reopened, "#working-time", "0s")
    assert has_element?(reopened, "#incorporation-limit")
    refute has_element?(reopened, "#publish-experience")

    {:ok, place, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/places/#{zone.id}")
    place |> form("#record-form", record: %{name: "A draft visitor"}) |> render_submit()
    assert has_element?(place, "#drafts article", "A draft visitor")
    refute has_element?(place, "#actors article", "A draft visitor")
  end

  test "stale form cannot overwrite newer authoring, and reconnect reloads only committed records",
       ctx do
    {:ok, first, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/places/bridge")
    {:ok, stale, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/places/bridge")
    first |> form("#record-form", record: %{name: "Edda"}) |> render_submit()
    stale |> form("#record-form", record: %{name: "Stale visitor"}) |> render_submit()
    assert has_element?(stale, "#flash-error", "changed since you opened")
    {:ok, reopened, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/places/bridge")
    assert has_element?(reopened, "#actors article", "Edda")
    refute has_element?(reopened, "#actors article", "Stale visitor")
    snapshot = Repo.get_by!(Snapshot, world_id: ctx.world.id, scope_kind: "published")
    assert {:ok, scene} = Snapshots.load(snapshot)
    assert map_size(scene.actors) == 5
  end

  test "role revocation removes editor and private state; tampered saves fail at authority",
       ctx do
    builder = Scope.for_user(user_fixture())
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "builder")
    conn = build_conn() |> log_in_user(builder.user)
    {:ok, view, _} = live(conn, ~p"/worlds/#{ctx.world.id}/places/bridge")
    assert has_element?(view, "#record-form")
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "viewer")
    view |> form("#record-form", record: %{name: "Unauthorized visitor"}) |> render_submit()
    refute has_element?(view, "#record-form")
    assert has_element?(view, "#flash-error", "permission changed")
    refute has_element?(view, "#items article", "Secret letter")

    assert {:error, :unauthorized} =
             Content.curate(
               builder,
               ctx.world.id,
               "bridge",
               0,
               nil,
               %{"kind" => "npc", "name" => "Forbidden"},
               "forged"
             )

    other = world_fixture()

    assert {:error, {:live_redirect, %{to: "/worlds"}}} =
             live(conn, ~p"/worlds/#{other.world.id}")

    assert {:error, {:live_redirect, %{to: "/worlds"}}} =
             live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{Ecto.UUID.generate()}")
  end

  test "claim conflicts give an actionable next step and do not start a second Experience", ctx do
    {:ok, one} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "First", "zone_id" => "bridge"},
        "first"
      )

    {:ok, _} = Experiences.start(ctx.owner, ctx.world.id, one.id, 0)

    {:ok, two} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "Second", "zone_id" => "bridge"},
        "second"
      )

    {:ok, view, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{two.id}")
    view |> element("#start-experience") |> render_click()
    assert has_element?(view, "#flash-error", "Reopen it from Experiences")
    assert has_element?(view, "#experiences article", "First")
    assert {:ok, %{status: "draft"}} = Experiences.get(ctx.owner, ctx.world.id, two.id)
  end

  test "durable outbox invalidation refreshes an open editor after a role is revoked", ctx do
    builder = Scope.for_user(user_fixture())
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "builder")
    conn = build_conn() |> log_in_user(builder.user)
    {:ok, view, _} = live(conn, ~p"/worlds/#{ctx.world.id}/places/bridge")
    assert has_element?(view, "#record-form")
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "viewer")
    {:ok, world} = Worlds.get_world(ctx.owner, ctx.world.id)
    outbox = Repo.get_by!(Outbox, world_id: world.id, cursor: world.cursor)
    assert :ok = perform_job(DeliverEvent, %{"outbox_id" => outbox.id}, repo: Repo)
    refute has_element?(view, "#record-form")
    refute has_element?(view, "#items article", "Secret letter")
    assert Repo.get!(Outbox, outbox.id).delivered_at
    assert :ok = perform_job(DeliverEvent, %{"outbox_id" => outbox.id}, repo: Repo)
    refute has_element?(view, "#record-form")
  end

  test "GM sees durable local consequences against the checkpoint without publishing them", ctx do
    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara"
      )

    ctx = experience_fixture(ctx)
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, _} = Session.propose(session, "help", %{type: "help", target_id: "moll"})
    {:ok, _} = Session.confirm(session, "help", "help")
    {:ok, view, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}")
    assert has_element?(view, "#working-changes article", "Mara · helped (fact)")
    assert has_element?(view, "#working-changes article", "effort: 10")
    assert has_element?(view, "#working-changes article", "effort: 9")
    assert has_element?(view, "#working-time", "60s")
    assert has_element?(view, "#published-time", "0s")
    assert {:ok, base} = Snapshots.load(ctx.published)

    refute Enum.any?(base.knowledge, fn {_id, fact} ->
             fact.kind == :fact and fact.predicate == "helped"
           end)

    assert Enum.any?(base.knowledge, fn {_id, fact} ->
             fact.kind == :belief and fact.predicate == "helped"
           end)
  end
end
