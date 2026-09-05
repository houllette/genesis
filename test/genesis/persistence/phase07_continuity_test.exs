defmodule Genesis.Persistence.Phase07ContinuityTest do
  use Genesis.DataCase, async: false
  @moduletag :capture_log
  import Genesis.Phase07Fixtures
  alias Genesis.Accounts.Scope
  alias Genesis.AccountsFixtures
  alias Genesis.Campaigns
  alias Genesis.Content
  alias Genesis.Content.Atlas
  alias Genesis.Core.Stock
  alias Genesis.Engine.Runtime
  alias Genesis.Engine.Session
  alias Genesis.Engine.World
  alias Genesis.Engine.WorldSupervisor
  alias Genesis.Experiences
  alias Genesis.Persistence.Event
  alias Genesis.Persistence.GlobalDependency
  alias Genesis.Persistence.GlobalPublication
  alias Genesis.Persistence.History
  alias Genesis.Persistence.Publication, as: PublicationOperation
  alias Genesis.Persistence.Reservation
  alias Genesis.Persistence.Snapshot
  alias Genesis.Persistence.Standing
  alias Genesis.Persistence.Tx
  alias Genesis.Repo
  alias Genesis.Travel
  alias Genesis.WorldStandings

  setup tags do
    ctx = active_world(Map.get(tags, :world_options, []))

    start_supervised!(
      {WorldSupervisor,
       registry: Genesis.Engine.Registry,
       world_id: ctx.world.id,
       generation: 0,
       owner: self(),
       storage: :postgres,
       observer: self()}
    )

    assert_receive {:genesis_world_started, world_pid}

    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, Map.merge(ctx, %{session: session, world_pid: world_pid})}
  end

  test "companion, delivery and sourced standing publish atomically across three places", ctx do
    assert {:ok, _} = act(ctx.session, "recruit", "orin", "invite")
    assert {:ok, _} = act(ctx.session, "agree", "orin", "agree")
    assert working(ctx, "bridge").actors["orin"].companion_of == "mara"
    exchange = %{"type" => "offer", "target_id" => "docks-representative", "quantity" => 1}

    assert {:ok, preview} =
             Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks", exchange)

    assert preview.party_size == 2

    assert {:ok, trip} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "mara",
               preview.token,
               "delivery"
             )

    assert {:ok, ^trip} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "mara",
               preview.token,
               "delivery"
             )

    docks = working(ctx, "docks")
    assert Stock.balance(docks, "mara", "ration") == 2
    assert Stock.balance(docks, "docks-representative", "ration") == 1
    assert docks.actors["orin"].companion_of == "mara"
    source = List.last(trip["event_ids"])

    assert {:ok, report} =
             WorldStandings.report(ctx.owner, ctx.world.id, ctx.experience.id, source, "report")

    assert report["standing"] == 1

    assert {:ok, ^report} =
             WorldStandings.report(ctx.owner, ctx.world.id, ctx.experience.id, source, "report")

    assert {:ok, %{"status" => "already_reported", "standing" => 1}} =
             WorldStandings.report(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               source,
               "duplicate-report"
             )

    assert {:ok, []} = WorldStandings.view(ctx.owner, ctx.world.id)

    assert {:ok, [%{standing: 1, status: "Working"}]} =
             WorldStandings.view(ctx.owner, ctx.world.id, ctx.experience.id)

    assert Repo.aggregate(GlobalDependency, :count) == 1
    [global] = GlobalPublication.rows(ctx.experience.id)
    assert {:ok, [_]} = GlobalPublication.replay(global)

    assert {:ok, onward} =
             Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "hill")

    assert {:ok, _} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "mara",
               onward.token,
               "onward"
             )

    assert working(ctx, "hill").actors["orin"].companion_of == nil
    revision = working(ctx, "bridge").revision

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, :ready, revision, "ready"}
             )

    assert {:ok, publication} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    assert {:ok, _} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, publication.id, "publish"})

    assert {:ok, [%{standing: 1, status: "Published", source_ids: [published_source]}]} =
             WorldStandings.view(ctx.owner, ctx.world.id)

    assert %Event{source_event_id: ^source} =
             Repo.get_by!(Event, world_id: ctx.world.id, core_event_id: published_source)

    assert Repo.aggregate(GlobalDependency, :count) == 0
    assert {:ok, hill} = Content.view(ctx.owner, ctx.world.id, "hill")
    assert Enum.any?(hill.actors, &(&1.id == "orin"))
    assert Enum.any?(hill.knowledge, &(&1.predicate == "companionship"))

    assert Repo.aggregate(
             from(s in Snapshot, where: s.experience_id == ^ctx.experience.id),
             :count
           ) == 3

    assert Repo.aggregate(from(s in Standing, where: s.scope_key == "published"), :count) == 1
    global = Repo.one!(from s in Standing, where: s.scope_key == "published")
    assert {:ok, data} = GlobalPublication.replay_published(global)
    assert data == global.data
    assert_two_campaigns(ctx, published_source)
  end

  test "a refused remote exchange leaves the actor, stock and footprint unchanged", ctx do
    before = working(ctx, "bridge")

    assert {:error, :insufficient_stock_or_capacity} =
             Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks", %{
               "type" => "offer",
               "target_id" => "docks-representative",
               "quantity" => 100
             })

    assert working(ctx, "bridge") == before

    refute Repo.exists?(
             from s in Snapshot,
               where: s.experience_id == ^ctx.experience.id and s.zone_id == "docks"
           )
  end

  test "a blocked delivery coordinator does not block an unrelated third Zone", ctx do
    {:ok, campaign} =
      Campaigns.create_campaign(
        ctx.owner,
        ctx.world.id,
        %{"name" => "Hill crew"},
        "hill-campaign"
      )

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        campaign.id,
        ctx.owner.user.id,
        "hill-courier",
        "hill-bind"
      )

    {:ok, exp} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        campaign.id,
        %{"name" => "Hill errand", "zone_id" => "hill", "participants" => ["hill-courier"]},
        "hill-exp"
      )

    {:ok, exp} = Experiences.start(ctx.owner, ctx.world.id, exp.id, 0)
    {:ok, hill} = Runtime.attach(ctx.owner, ctx.world.id, exp.id, "hill-courier")
    parent = self()

    fault = fn stage ->
      if stage == :transfer_after_prepare do
        send(parent, {:prepared, self()})

        receive do
          :continue -> :ok
        end
      end
    end

    :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})

    {:ok, preview} =
      Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks", %{
        "type" => "offer",
        "target_id" => "docks-representative",
        "quantity" => 1
      })

    task_sup = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(task_sup, fn ->
        Travel.move(ctx.owner, ctx.world.id, ctx.experience.id, "mara", preview.token, "delivery")
      end)

    assert_receive {:prepared, worker}

    try do
      assert {:ok, %{zone_id: "hill"}} = Session.view(hill)
      assert {:ok, _} = act(hill, "help", "hill-representative", "unrelated")
      assert {:ok, %{revision: 1}} = Session.view(hill)
      assert {:error, :transfer_busy} = Session.view(ctx.session)
      assert World.identity(ctx.world_pid) == {ctx.world.id, 0}
    after
      send(worker, :continue)
    end

    assert {:ok, _} = Task.await(task)
    assert working(ctx, "docks").actors["mara"].id == "mara"
  end

  for stage <- [
        :transfer_after_prepare,
        :transfer_before_commit,
        :transfer_after_commit,
        :transfer_after_first_install
      ] do
    @tag stage: stage
    test "party delivery recovery at #{stage} conserves every actor and receipt", ctx do
      {:ok, _} = act(ctx.session, "recruit", "orin", "invite")
      {:ok, _} = act(ctx.session, "agree", "orin", "agree")
      fault = fn stage -> if stage == ctx.stage, do: exit(:injected_failure), else: :ok end
      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})

      {:ok, preview} =
        Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks", %{
          "type" => "sell",
          "target_id" => "docks-merchant",
          "quantity" => 1
        })

      assert {:error, _} =
               Travel.move(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 "mara",
                 preview.token,
                 "delivery"
               )

      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: []})

      assert {:ok, receipt} =
               Travel.move(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 "mara",
                 preview.token,
                 "delivery"
               )

      assert {:ok, ^receipt} =
               Travel.move(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 "mara",
                 preview.token,
                 "delivery"
               )

      left = working(ctx, "bridge")
      right = working(ctx, "docks")
      refute Map.has_key?(left.actors, "orin")
      refute Map.has_key?(left.items, "orin-satchel")
      assert right.items["orin-satchel"].owner == {:actor, "orin"}
      assert right.actors["orin"].commitment["trips_left"] == 1
      assert Stock.balance(right, "mara", "grain") == 1
      assert Stock.balance(right, "mara", "coin") == 105
      assert length(receipt["event_ids"]) == 3
    end
  end

  test "global snapshot tampering after sealing prevents any publication", ctx do
    {:ok, proposal} =
      Session.propose(ctx.session, "offer", %{type: "offer", target_id: "reed", quantity: 1})

    {:ok, receipt} = Session.confirm(ctx.session, "offer", proposal.id)
    core_id = hd(receipt.effects).id
    source = Repo.get_by!(Event, world_id: ctx.world.id, core_event_id: core_id).id
    {:ok, _} = WorldStandings.report(ctx.owner, ctx.world.id, ctx.experience.id, source, "report")

    {:ok, _} =
      Runtime.call(
        ctx.owner,
        ctx.world.id,
        {:status, ctx.experience.id, :ready, working(ctx, "bridge").revision, "ready"}
      )

    [row] = GlobalPublication.rows(ctx.experience.id)
    Tx.update!(row, %{data: Map.put(row.data, "standing", 99)})

    assert {:error, :corrupt_global_state} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    assert {:ok, []} = WorldStandings.view(ctx.owner, ctx.world.id)
  end

  for side <- [:source, :destination],
      stage <- [:transfer_after_prepare, :transfer_after_commit] do
    @tag side: side, stage: stage
    test "#{side} Zone death at #{stage} cannot separate a delivery party", ctx do
      {:ok, _} = act(ctx.session, "recruit", "orin", "invite")
      {:ok, _} = act(ctx.session, "agree", "orin", "agree")
      install_barrier(ctx, ctx.stage)

      {:ok, preview} =
        Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks", %{
          "type" => "sell",
          "target_id" => "docks-merchant",
          "quantity" => 1
        })

      tasks = start_supervised!(Task.Supervisor)

      task =
        Task.Supervisor.async_nolink(tasks, fn ->
          Travel.move(
            ctx.owner,
            ctx.world.id,
            ctx.experience.id,
            "mara",
            preview.token,
            "zone-death"
          )
        end)

      assert_receive {:barrier, worker}

      {_ref, entry} =
        Enum.find(:sys.get_state(ctx.world_pid).transfers, fn {_ref, entry} ->
          entry.pid == worker
        end)

      zone = Enum.at(entry.zones, if(ctx.side == :source, do: 0, else: 1))
      ref = Process.monitor(zone)
      Process.exit(zone, :kill)
      assert_receive {:DOWN, ^ref, :process, ^zone, :killed}
      send(worker, :continue)
      assert {:error, :transfer_interrupted} = Task.await(task)
      assert Repo.aggregate(Reservation, :count) == 0
      place = if ctx.stage == :transfer_after_commit, do: "docks", else: "bridge"
      assert working(ctx, place).actors["orin"].companion_of == "mara"
      assert working(ctx, place).items["orin-satchel"].owner == {:actor, "orin"}
      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: []})

      assert {:ok, receipt} =
               Travel.move(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 "mara",
                 preview.token,
                 "zone-death"
               )

      assert length(receipt["event_ids"]) == 3
      assert working(ctx, "docks").actors["orin"].commitment["trips_left"] == 1
      assert Stock.balance(working(ctx, "docks"), "mara", "coin") == 105
      refute Map.has_key?(working(ctx, "bridge").actors, "orin")
    end
  end

  for stage <- [
        :publication_after_prepare,
        :before_commit,
        :after_commit,
        :publication_after_first_install,
        :after_install
      ] do
    @tag stage: stage
    test "World standing and relief flag recover together at #{stage}", ctx do
      preview = reported_publication(ctx)
      fault = fn stage -> if stage == ctx.stage, do: exit(:injected_failure), else: :ok end
      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})

      assert {:error, :publication_interrupted} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: []})

      assert {:ok, receipt} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert {:ok, ^receipt} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert {:ok, [%{standing: 1, relief_supported: true}]} =
               WorldStandings.view(ctx.owner, ctx.world.id)

      row = Repo.one!(from r in Standing, where: r.scope_key == "published")
      assert {:ok, data} = GlobalPublication.replay_published(row)
      assert data == row.data
      assert Repo.aggregate(GlobalDependency, :count) == 0

      assert Repo.aggregate(
               from(e in Event,
                 where: e.kind == "world" and is_nil(e.actor_id) and not is_nil(e.source_event_id)
               ),
               :count
             ) == 1
    end
  end

  test "a committed standing is unreadable until publication caches are installed", ctx do
    preview = reported_publication(ctx)
    install_barrier(ctx, :after_commit)
    tasks = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})
      end)

    assert_receive {:barrier, worker}

    try do
      assert Repo.get_by!(PublicationOperation, world_id: ctx.world.id).status == "committed"
      assert {:error, :publication_busy} = WorldStandings.view(ctx.owner, ctx.world.id)

      assert {:error, :publication_busy} =
               WorldStandings.view(ctx.owner, ctx.world.id, ctx.experience.id)

      assert {:error, :publication_busy} = History.page(ctx.owner, ctx.world.id)
      assert World.identity(ctx.world_pid) == {ctx.world.id, 0}
    after
      send(worker, :continue)
    end

    assert {:ok, _} = Task.await(task)
    assert {:ok, [%{standing: 1}]} = WorldStandings.view(ctx.owner, ctx.world.id)
  end

  test "a later Experience extends published standing without rewriting prior sources", ctx do
    first = reported_publication(ctx)
    assert {:ok, _} = Runtime.call(ctx.owner, ctx.world.id, {:incorporate, first.id, "publish"})
    assert {:ok, [%{source_ids: [original]}]} = WorldStandings.view(ctx.owner, ctx.world.id)
    ctx = Genesis.WorldFixtures.experience_fixture(ctx, request_id: "later-experience")
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    ctx = %{ctx | session: session}
    second = reported_publication(ctx)
    assert {:ok, [%{standing: 1}]} = WorldStandings.view(ctx.owner, ctx.world.id)

    assert {:ok, _} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, second.id, "publish-later"})

    assert {:ok, [%{standing: 2, source_ids: [^original, later]}]} =
             WorldStandings.view(ctx.owner, ctx.world.id)

    refute later == original
    row = Repo.one!(from r in Standing, where: r.scope_key == "published")
    assert {:ok, data} = GlobalPublication.replay_published(row)
    assert data == row.data
  end

  @tag world_options: [ruleset: "cyberpunk_local", profile: "mutual_aid"]
  test "secular barter delivery uses the same party and conserved stock protocol", ctx do
    {:ok, _} = act(ctx.session, "recruit", "orin", "invite")
    {:ok, _} = act(ctx.session, "agree", "orin", "agree")

    {:ok, preview} =
      Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks", %{
        "type" => "barter",
        "target_id" => "docks-merchant",
        "quantity" => 2
      })

    assert {:ok, receipt} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "mara",
               preview.token,
               "barter-delivery"
             )

    state = working(ctx, "docks")
    assert state.settlement["profile"]["id"] == "mutual_aid"
    assert Stock.balance(state, "mara", "grain") == 6
    assert Stock.balance(state, "mara", "ration") == 1
    assert Stock.balance(state, "docks-merchant", "grain") == 8
    assert Stock.balance(state, "docks-merchant", "ration") == 2
    assert state.actors["orin"].companion_of == "mara"
    assert length(receipt["event_ids"]) == 3
  end

  test "recognition rejects non-contributions without creating a global dependency", ctx do
    {:ok, result} = act(ctx.session, "help", "reed", "help")
    source = Repo.get_by!(Event, world_id: ctx.world.id, core_event_id: hd(result.effects).id)

    assert {:error, :report_unavailable} =
             WorldStandings.report(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               source.id,
               "report"
             )

    assert Repo.aggregate(GlobalDependency, :count) == 0
    assert {:ok, []} = WorldStandings.view(ctx.owner, ctx.world.id, ctx.experience.id)
  end

  test "a sealed standing cannot be redirected to another actor", ctx do
    _preview = reported_publication(ctx)
    [row] = GlobalPublication.rows(ctx.experience.id)
    Tx.update!(row, %{actor_id: "orin"})

    assert {:error, :sealed_footprint_changed} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    assert {:ok, []} = WorldStandings.view(ctx.owner, ctx.world.id)
  end

  defp reported_publication(ctx) do
    {:ok, proposal} =
      Session.propose(ctx.session, "offer", %{type: "offer", target_id: "reed", quantity: 1})

    {:ok, receipt} = Session.confirm(ctx.session, "offer", proposal.id)
    source = Repo.get_by!(Event, world_id: ctx.world.id, core_event_id: hd(receipt.effects).id).id
    {:ok, _} = WorldStandings.report(ctx.owner, ctx.world.id, ctx.experience.id, source, "report")

    {:ok, _} =
      Runtime.call(
        ctx.owner,
        ctx.world.id,
        {:status, ctx.experience.id, :ready, working(ctx, "bridge").revision, "ready"}
      )

    {:ok, preview} =
      Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    preview
  end

  defp install_barrier(ctx, boundary) do
    parent = self()

    fault = fn stage ->
      if stage == boundary do
        send(parent, {:barrier, self()})
        receive do: (:continue -> :ok)
      end
    end

    :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})
  end

  defp act(session, type, target, request) do
    with {:ok, proposal} <- Session.propose(session, request, %{type: type, target_id: target}),
         do: Session.confirm(session, request, proposal.id)
  end

  defp assert_two_campaigns(ctx, published_source) do
    {:ok, second} =
      Campaigns.create_campaign(ctx.owner, ctx.world.id, %{"name" => "Later visitors"}, "later")

    viewers =
      for {campaign, label} <- [{ctx.campaign, "Dock"}, {second, "Visitor"}] do
        viewer = Scope.for_user(AccountsFixtures.user_fixture())

        {:ok, _} =
          Campaigns.add_member(
            ctx.owner,
            ctx.world.id,
            campaign.id,
            viewer.user.id,
            "spectator",
            "member-#{label}"
          )

        {:ok, _} =
          Atlas.save(
            ctx.owner,
            ctx.world.id,
            nil,
            0,
            %{
              "kind" => "article",
              "name" => "#{label} plans",
              "body" => "#{label} private interpretation, not an engine fact",
              "visibility" => "party",
              "campaign_id" => campaign.id
            },
            "notes-#{label}"
          )

        {viewer, label}
      end

    for {viewer, label} <- viewers do
      assert {:ok, %{record: %{zone_id: "hill", name: "Orin", editable: false}}} =
               Atlas.get(viewer, ctx.world.id, "actor:orin")

      assert {:ok, bridge} = Content.view(viewer, ctx.world.id, "bridge")
      refute Enum.any?(bridge.actors, &(&1.id == "orin"))
      assert {:ok, %{records: [note], count: 1}} = Atlas.search(viewer, ctx.world.id, "plans")
      assert note.name == "#{label} plans"
      assert {:ok, []} = WorldStandings.view(viewer, ctx.world.id)
      assert {:error, :unavailable} = History.source(viewer, ctx.world.id, published_source)
    end

    assert {:ok, %{scope_kind: "world", sources: [_ | _]}} =
             History.source(ctx.owner, ctx.world.id, published_source)
  end
end
