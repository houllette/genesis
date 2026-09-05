defmodule Genesis.Persistence.TransfersTest do
  use Genesis.DataCase, async: false
  @moduletag :capture_log
  import Ecto.Query
  import Genesis.WorldFixtures
  alias Genesis.{Campaigns, Content, Repo, Travel, Workspace, WorldNetwork}
  alias Genesis.Engine.{Runtime, Session, World, WorldSupervisor}

  alias Genesis.Persistence.{
    Checkpoint,
    Claim,
    Event,
    Footprints,
    Replay,
    Reservation,
    Snapshot,
    Snapshots,
    Transfer
  }

  setup do
    ctx = world_fixture(zero_duration: true, ruleset: "fantasy_local")

    start_supervised!(
      {WorldSupervisor,
       registry: Genesis.Engine.Registry,
       world_id: ctx.world.id,
       generation: ctx.world.generation,
       owner: self(),
       storage: :postgres,
       observer: self()}
    )

    assert_receive {:genesis_world_started, world}

    {:ok, %{"zone_id" => docks}} =
      Content.create_zone(ctx.owner, ctx.world.id, %{"name" => "Docks"}, "docks")

    edge = %{
      "type" => "connection",
      "from" => "bridge",
      "to" => docks,
      "condition" => "open",
      "capacity" => 4,
      "visibility" => "public"
    }

    {:ok, _} =
      WorldNetwork.save(
        ctx.owner,
        ctx.world.id,
        %{generation: ctx.world.generation, revision: 0},
        edge,
        "link"
      )

    {:ok, _} =
      WorldNetwork.save(
        ctx.owner,
        ctx.world.id,
        %{generation: ctx.world.generation, revision: 1},
        %{edge | "from" => docks, "to" => "bridge"},
        "return-link"
      )

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara",
        "bind"
      )

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "courier",
        "bind-courier"
      )

    ctx = experience_fixture(ctx, participants: ["mara", "courier"])
    {:ok, Map.merge(ctx, %{docks: docks, world_pid: world})}
  end

  test "preview is read-only; confirmed movement preserves knowledge and rebinds the existing Session",
       ctx do
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    assert {:ok, %{zone_id: "bridge"}} = Session.view(session)
    token = :sys.get_state(session).token
    {:ok, before} = Snapshots.load(ctx.snapshot)

    assert {:ok, quote} =
             Session.propose(session, "old-quote", %{type: "help", target_id: "moll"})

    before_claims = Repo.aggregate(Claim, :count)

    assert {:ok, preview} =
             Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", ctx.docks)

    assert Repo.aggregate(Claim, :count) == before_claims

    assert {:ok, result} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "mara",
               preview.token,
               "travel"
             )

    assert result["to"] == ctx.docks
    assert {:ok, view} = Session.view(session)
    assert view.zone_id == ctx.docks

    assert {:error, :unauthorized} =
             World.authorize(ctx.world_pid, token, before.scope, "bridge")

    assert {:error, :unavailable} = Session.confirm(session, "old-confirm", quote.id)
    carried = before.items |> Map.values() |> Enum.filter(&(&1.owner == {:actor, "mara"}))

    assert Enum.sort_by(view.items, & &1.id) ==
             Enum.sort_by(Enum.map(carried, &Map.from_struct/1), & &1.id)

    assert Enum.any?(view.knowledge, &(&1.id == "rumor"))
    assert {:ok, rows} = Footprints.snapshots(ctx.experience)
    assert length(rows) == 2
    assert {:ok, pairs} = Footprints.load(rows)
    assert Enum.count(pairs, fn {_row, scene} -> Map.has_key?(scene.actors, "mara") end) == 1

    assert Enum.all?(pairs, fn {_row, scene} ->
             scene.elapsed == 0 and scene.time.value == ctx.seed.time.value
           end)

    for {row, scene} <- pairs do
      cp =
        Repo.one!(
          from c in Checkpoint, where: c.snapshot_id == ^row.id, order_by: c.cursor, limit: 1
        )

      assert {:ok, ^scene} = Replay.restore(ctx.owner, ctx.world.id, cp.id)
      assert {:ok, _published, base} = Footprints.base(row)
      assert base.scope.kind == :published
    end

    assert Repo.aggregate(Reservation, :count) == 0
    assert Repo.get!(Transfer, result["id"]).status == "installed"
    assert Repo.get!(Snapshot, ctx.published.id).digest == ctx.published.digest
    count = Repo.aggregate(Event, :count)

    assert {:ok, ^result} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "mara",
               preview.token,
               "travel"
             )

    assert Repo.aggregate(Event, :count) == count

    assert {:error, :request_conflict} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "mara",
               %{preview.token | "to" => "bridge"},
               "travel"
             )

    assert {:ok, destination} =
             Workspace.experience_view(ctx.owner, ctx.world.id, ctx.experience.id, ctx.docks)

    assert destination.zone_id == ctx.docks

    assert {:ok, back} =
             Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "bridge")

    assert {:ok, _} =
             Travel.move(ctx.owner, ctx.world.id, ctx.experience.id, "mara", back.token, "return")

    assert {:ok, %{zone_id: "bridge"}} = Session.view(session)
  end

  test "stale previews cannot move or claim a destination", ctx do
    {:ok, preview} = Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", ctx.docks)
    claims = Repo.aggregate(Claim, :count)

    assert {:error, :stale_transfer} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "mara",
               %{preview.token | "source_revision" => 99},
               "stale"
             )

    assert Repo.aggregate(Claim, :count) == claims
    assert Repo.aggregate(Transfer, :count) == 0
    assert {:ok, scene} = Snapshots.load(ctx.snapshot)
    assert Map.has_key?(scene.actors, "mara")
  end

  test "opposite directions return busy without blocking the World and must re-preview after the winner",
       ctx do
    {:ok, outward} = Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", ctx.docks)

    {:ok, _} =
      Travel.move(ctx.owner, ctx.world.id, ctx.experience.id, "mara", outward.token, "out")

    {:ok, back} = Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "bridge")

    {:ok, other} =
      Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "courier", ctx.docks)

    parent = self()

    fault = fn stage ->
      if stage == :transfer_after_prepare do
        send(parent, {:reserved, self()})
        receive do: (:continue -> :ok)
      else
        :ok
      end
    end

    :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})
    tasks = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        Travel.move(ctx.owner, ctx.world.id, ctx.experience.id, "mara", back.token, "back")
      end)

    assert_receive {:reserved, worker}
    assert World.identity(ctx.world_pid) == {ctx.world.id, ctx.world.generation}

    assert {:error, :transfer_busy} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "courier",
               other.token,
               "other"
             )

    assert {:error, :transfer_busy} =
             Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "courier")

    send(worker, :continue)
    assert {:ok, _} = Task.await(task)
    :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: []})

    assert {:error, :stale_transfer} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "courier",
               other.token,
               "other"
             )

    {:ok, fresh} =
      Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "courier", ctx.docks)

    assert {:ok, _} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "courier",
               fresh.token,
               "other"
             )

    {:ok, rows} = Footprints.snapshots(ctx.experience)
    {:ok, pairs} = Footprints.load(rows)
    assert Enum.count(pairs, fn {_row, state} -> Map.has_key?(state.actors, "mara") end) == 1
    assert Enum.count(pairs, fn {_row, state} -> Map.has_key?(state.actors, "courier") end) == 1
  end

  for stage <- [
        :transfer_after_prepare,
        :transfer_before_commit,
        :transfer_after_commit,
        :transfer_after_first_install
      ] do
    @tag stage: stage
    test "coordinator interruption at #{stage} recovers a single durable outcome", ctx do
      {:ok, preview} =
        Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", ctx.docks)

      fault = fn stage -> if stage == ctx.stage, do: exit({:injected, stage}), else: :ok end
      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})

      assert {:error, :transfer_interrupted} =
               Travel.move(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 "mara",
                 preview.token,
                 "crash"
               )

      assert Repo.aggregate(Reservation, :count) == 0
      assert {:ok, rows} = Footprints.snapshots(ctx.experience)
      assert length(rows) == 2
      assert {:ok, pairs} = Footprints.load(rows)

      expected =
        if ctx.stage in [:transfer_after_commit, :transfer_after_first_install],
          do: ctx.docks,
          else: "bridge"

      assert [{_row, scene}] =
               Enum.filter(pairs, fn {_row, scene} -> Map.has_key?(scene.actors, "mara") end)

      assert scene.zone_id == expected

      assert scene.knowledge["rumor"] ==
               ctx.seed.knowledge["rumor"] |> Map.put(:scope, scene.scope)

      assert Repo.get!(Snapshot, ctx.published.id).digest == ctx.published.digest
      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: []})

      assert {:ok, result} =
               Travel.move(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 "mara",
                 preview.token,
                 "crash"
               )

      assert Repo.get!(Transfer, result["id"]).status == "installed"
      assert length(result["event_ids"]) == 2

      assert {:ok, ^result} =
               Travel.move(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 "mara",
                 preview.token,
                 "crash"
               )

      {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
      assert {:ok, %{zone_id: zone}} = Session.view(session)
      assert zone == ctx.docks
    end
  end

  test "pause and resume gate every visited place without changing untouched revisions", ctx do
    {:ok, preview} = Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", ctx.docks)

    {:ok, _} =
      Travel.move(ctx.owner, ctx.world.id, ctx.experience.id, "mara", preview.token, "move")

    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, origin} = Workspace.experience_view(ctx.owner, ctx.world.id, ctx.experience.id)
    {:ok, destination} = Session.view(session)

    assert {:ok, paused} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, :pause, origin.revision, "pause"}
             )

    assert {:ok, paused_view} = Session.view(session)
    assert paused_view.status == :paused
    assert paused_view.revision == destination.revision

    assert {:error, :paused} =
             Session.propose(session, "paused", %{type: "help", target_id: "mara"})

    assert {:ok, %{status: :paused}} =
             Workspace.experience_view(ctx.owner, ctx.world.id, ctx.experience.id, ctx.docks)

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, :resume, paused["revision"], "resume"}
             )

    assert {:ok, resumed_view} = Session.view(session)
    assert resumed_view.status == :active
    assert resumed_view.revision == destination.revision
    assert {:ok, _} = Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "bridge")
  end

  for stage <- [:transfer_after_prepare, :transfer_after_commit] do
    @tag stage: stage
    test "World restart at #{stage} cold-recovers before new Sessions are admitted", ctx do
      {:ok, preview} =
        Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", ctx.docks)

      parent = self()

      fault = fn stage ->
        if stage == ctx.stage do
          send(parent, {:at_boundary, self()})
          receive do: (:continue -> :ok)
        else
          :ok
        end
      end

      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})
      tasks = start_supervised!(Task.Supervisor)

      task =
        Task.Supervisor.async_nolink(tasks, fn ->
          catch_exit(
            Travel.move(
              ctx.owner,
              ctx.world.id,
              ctx.experience.id,
              "mara",
              preview.token,
              "restart"
            )
          )
        end)

      assert_receive {:at_boundary, worker}
      worker_ref = Process.monitor(worker)
      world_ref = Process.monitor(ctx.world_pid)
      GenServer.stop(ctx.world_pid, :normal)
      assert_receive {:DOWN, ^world_ref, :process, _, :normal}
      assert_receive {:DOWN, ^worker_ref, :process, ^worker, _}
      assert_receive {:genesis_world_started, replacement}
      refute replacement == ctx.world_pid
      assert {_, {GenServer, :call, _}} = Task.await(task)
      assert Repo.aggregate(Reservation, :count) == 0
      {:ok, row} = Footprints.actor_snapshot(ctx.experience, "mara")
      assert row.zone_id == if(ctx.stage == :transfer_after_commit, do: ctx.docks, else: "bridge")

      assert {:ok, result} =
               Travel.move(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 "mara",
                 preview.token,
                 "restart"
               )

      assert result["to"] == ctx.docks
    end
  end

  for side <- [:source, :destination],
      boundary <- [:transfer_after_prepare, :transfer_after_commit] do
    @tag side: side, zone_boundary: boundary
    test "#{side} Zone failure at #{boundary} preserves the durable decision and footprint claims",
         ctx do
      {:ok, preview} =
        Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", ctx.docks)

      parent = self()

      fault = fn stage ->
        if stage == ctx.zone_boundary do
          send(parent, {:prepared, self()})
          receive do: (:continue -> :ok)
        else
          :ok
        end
      end

      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})
      tasks = start_supervised!(Task.Supervisor)

      task =
        Task.Supervisor.async_nolink(tasks, fn ->
          Travel.move(
            ctx.owner,
            ctx.world.id,
            ctx.experience.id,
            "mara",
            preview.token,
            "zone-crash"
          )
        end)

      assert_receive {:prepared, worker}

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
      {:ok, row} = Footprints.actor_snapshot(ctx.experience, "mara")

      assert row.zone_id ==
               if(ctx.zone_boundary == :transfer_after_commit, do: ctx.docks, else: "bridge")

      assert {:ok, rows} = Footprints.snapshots(ctx.experience)
      assert length(rows) == 2
      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: []})

      assert {:ok, _} =
               Travel.move(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 "mara",
                 preview.token,
                 "zone-crash"
               )
    end
  end
end
