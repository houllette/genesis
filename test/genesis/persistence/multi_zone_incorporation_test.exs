defmodule Genesis.Persistence.MultiZoneIncorporationTest do
  use Genesis.DataCase, async: false
  @moduletag :capture_log
  alias Genesis.{Campaigns, Content, Experiences, Repo, Travel, Workspace, WorldNetwork}
  alias Genesis.Engine.{Runtime, World, WorldSupervisor}

  alias Genesis.Persistence.{
    Checkpoint,
    Claim,
    Curation,
    Entity,
    Event,
    Experience,
    Footprints,
    History,
    Incorporation,
    Publication,
    Replay,
    Snapshot,
    Snapshots,
    Tx
  }

  import Genesis.WorldFixtures

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

    {:ok, _} =
      WorldNetwork.save(
        ctx.owner,
        ctx.world.id,
        %{generation: ctx.world.generation, revision: 0},
        %{
          "type" => "connection",
          "from" => "bridge",
          "to" => docks,
          "condition" => "open",
          "capacity" => 4,
          "visibility" => "public"
        },
        "link"
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

    ctx = experience_fixture(ctx)
    {:ok, quote} = Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", docks)

    {:ok, _} =
      Travel.move(ctx.owner, ctx.world.id, ctx.experience.id, "mara", quote.token, "travel")

    {:ok, Map.merge(ctx, %{docks: docks, world_pid: world})}
  end

  test "seal and publish every visited place, preserving ownership and source-linked replay",
       ctx do
    seal(ctx)
    completion = Repo.get!(Experience, ctx.experience.id).completion
    assert completion["format"] == 2
    assert length(completion["zones"]) == 2

    assert {:ok, preview} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    assert Enum.sort(preview.zone_ids) == Enum.sort(["bridge", ctx.docks])

    assert {:ok, result} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert {:ok, ^result} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert length(result["snapshot_ids"]) == 2
    assert result["world_time"] == 0
    refute Repo.exists?(from c in Claim, where: c.experience_id == ^ctx.experience.id)
    assert Repo.get!(Experience, ctx.experience.id).completion == completion

    assert Repo.get_by!(Entity, world_id: ctx.world.id, kind: "actor", entity_id: "mara").zone_id ==
             ctx.docks

    assert Repo.get_by!(Entity, world_id: ctx.world.id, kind: "item", entity_id: "mara-coin").zone_id ==
             ctx.docks

    assert {:ok, %{actors: actors}} = Content.view(ctx.owner, ctx.world.id, "bridge")
    refute Enum.any?(actors, &(&1.id == "mara"))

    assert {:ok, %{actors: actors, knowledge: knowledge}} =
             Content.view(ctx.owner, ctx.world.id, ctx.docks)

    assert Enum.any?(actors, &(&1.id == "mara"))
    assert Enum.any?(knowledge, &(&1.id == "rumor" and &1.scope.kind == :published))

    sources =
      Repo.all(
        from e in Event, where: e.experience_id == ^ctx.experience.id and not is_nil(e.actor_id)
      )

    published =
      Repo.all(
        from e in Event, where: e.world_id == ^ctx.world.id and not is_nil(e.source_event_id)
      )

    assert Enum.sort(Enum.map(published, & &1.source_event_id)) ==
             Enum.sort(Enum.map(sources, & &1.id))

    for id <- result["snapshot_ids"] do
      row = Repo.get!(Snapshot, id)
      {:ok, final} = Snapshots.load(row)

      cp =
        Repo.one!(from c in Checkpoint, where: c.snapshot_id == ^id, order_by: c.cursor, limit: 1)

      assert {:ok, ^final} = Replay.restore(ctx.owner, ctx.world.id, cp.id)
    end
  end

  test "a change to a non-origin sealed snapshot invalidates review", ctx do
    seal(ctx)
    {:ok, rows} = Footprints.snapshots(ctx.experience)
    row = Enum.find(rows, &(&1.zone_id == ctx.docks))
    {:ok, scene} = Snapshots.load(row)
    Snapshots.save!(row, %{scene | revision: scene.revision + 1})

    assert {:error, :sealed_footprint_changed} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    assert Repo.get!(Experience, ctx.experience.id).status == "ready"
  end

  test "sealing never blocks the World's authorization mailbox while waiting for its Zone", ctx do
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, nil)
    zone = :sys.get_state(session).zone
    origin = Repo.get_by!(Snapshot, experience_id: ctx.experience.id, zone_id: "bridge")
    :sys.suspend(zone)

    request =
      :gen_server.send_request(
        ctx.world_pid,
        {:durable, ctx.owner, {:status, ctx.experience.id, :ready, origin.revision, "seal"}}
      )

    try do
      assert World.identity(ctx.world_pid) == {ctx.world.id, ctx.world.generation}
    after
      :sys.resume(zone)
    end

    assert {:reply, {:ok, %{"status" => "ready"}}} = :gen_server.receive_response(request, 5000)
  end

  test "sealed source payloads and audiences cannot change under an unchanged event ID", ctx do
    seal(ctx)

    source =
      Repo.one!(
        from e in Event,
          where: e.experience_id == ^ctx.experience.id and not is_nil(e.actor_id),
          order_by: e.cursor,
          limit: 1
      )

    Tx.update!(source, %{audience_users: []})

    assert {:error, :sealed_footprint_changed} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})
  end

  for boundary <- [
        :publication_after_prepare,
        :before_commit,
        :after_commit,
        :publication_after_first_install,
        :after_install
      ] do
    @tag boundary: boundary
    test "recovers a coordinator interruption at #{boundary} without duplicate publication",
         ctx do
      seal(ctx)

      {:ok, preview} =
        Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

      fault = fn stage -> if stage == ctx.boundary, do: exit({:injected, stage}), else: :ok end
      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})

      assert {:error, :publication_interrupted} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: []})
      op = Repo.get_by!(Publication, world_id: ctx.world.id)

      expected =
        if ctx.boundary in [:publication_after_prepare, :before_commit],
          do: "aborted",
          else: "installed"

      assert op.status == expected

      assert {:ok, result} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert {:ok, ^result} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert Repo.aggregate(
               from(e in Event,
                 where: e.world_id == ^ctx.world.id and not is_nil(e.source_event_id)
               ),
               :count
             ) == 2

      assert Repo.get_by!(Entity, world_id: ctx.world.id, kind: "actor", entity_id: "mara").zone_id ==
               ctx.docks
    end
  end

  for boundary <- [:publication_after_prepare, :publication_after_first_install] do
    @tag boundary: boundary
    test "fences native reads, history and competing writes at #{boundary} while World remains responsive",
         ctx do
      seal(ctx)

      {:ok, preview} =
        Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

      parent = self()

      fault = fn stage ->
        if stage == ctx.boundary do
          send(parent, {:publication_barrier, self()})

          receive do
            :continue -> :ok
          end
        end
      end

      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})
      tasks = start_supervised!(Task.Supervisor)

      task =
        Task.Supervisor.async_nolink(tasks, fn ->
          Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})
        end)

      assert_receive {:publication_barrier, worker}, 2000
      assert World.identity(ctx.world_pid) == {ctx.world.id, ctx.world.generation}
      assert {:error, :publication_busy} = Content.view(ctx.owner, ctx.world.id, ctx.docks)

      assert {:error, :publication_busy} =
               Workspace.experience_footprint(ctx.owner, ctx.world.id, ctx.experience.id)

      assert {:error, :publication_busy} = WorldNetwork.view(ctx.owner, ctx.world.id)
      assert {:error, :publication_busy} = History.page(ctx.owner, ctx.world.id)

      assert {:error, :publication_busy} =
               Incorporation.receipt(
                 ctx.owner,
                 ctx.world.id,
                 preview.id,
                 "publish"
               )

      assert {:error, :publication_busy} =
               Curation.create_zone(
                 ctx.owner,
                 ctx.world.id,
                 %{"name" => "Competing"},
                 "compete"
               )

      assert {:error, :publication_busy} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "second"})

      send(worker, :continue)
      assert {:ok, _} = Task.await(task, 5000)
      assert {:ok, _} = Content.view(ctx.owner, ctx.world.id, ctx.docks)
    end
  end

  for target <- [:zone, :world],
      boundary <- [:publication_after_prepare, :publication_after_first_install] do
    @tag target: target, boundary: boundary
    test "recovers #{target} loss at #{boundary} from durable evidence", ctx do
      seal(ctx)

      {:ok, preview} =
        Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

      parent = self()

      fault = fn stage ->
        if stage == ctx.boundary do
          send(parent, {:publication_barrier, self()})

          receive do
            :continue -> :ok
          end
        end
      end

      :sys.replace_state(ctx.world_pid, &%{&1 | zone_opts: [fault: fault]})
      tasks = start_supervised!(Task.Supervisor)

      task =
        Task.Supervisor.async_nolink(tasks, fn ->
          try do
            Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})
          catch
            :exit, reason -> {:lost_reply, reason}
          end
        end)

      assert_receive {:publication_barrier, worker}, 2000
      entry = :sys.get_state(ctx.world_pid).publication

      victim =
        if ctx.target == :world, do: ctx.world_pid, else: entry.zones |> List.last() |> elem(0)

      monitor = Process.monitor(victim)
      Process.exit(victim, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^victim, :killed}
      if ctx.target == :zone, do: send(worker, :continue)
      result = Task.await(task, 5000)

      assert match?({:error, :publication_interrupted}, result) or
               match?({:lost_reply, _}, result)

      world =
        if ctx.target == :world do
          assert_receive {:genesis_world_started, restarted}, 2000
          restarted
        else
          ctx.world_pid
        end

      :sys.replace_state(world, &%{&1 | zone_opts: []})

      if ctx.boundary == :publication_after_prepare do
        assert {:ok, %{id: id}} =
                 Runtime.call(
                   ctx.owner,
                   ctx.world.id,
                   {:preview_incorporation, ctx.experience.id}
                 )

        assert id == preview.id
      end

      assert {:ok, _} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert Repo.get_by!(Publication, world_id: ctx.world.id).status ==
               "installed"

      assert Repo.get_by!(Entity, world_id: ctx.world.id, kind: "item", entity_id: "mara-coin").zone_id ==
               ctx.docks
    end
  end

  defp seal(ctx) do
    origin = Repo.get_by!(Snapshot, experience_id: ctx.experience.id, zone_id: "bridge")

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, :ready, origin.revision, "seal"}
             )
  end

  test "a later Experience can claim the actor and carried inventory at their incorporated destination",
       ctx do
    seal(ctx)

    {:ok, preview} =
      Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    {:ok, _} = Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    {:ok, next} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "Next gathering", "zone_id" => ctx.docks, "participants" => ["mara"]},
        "next"
      )

    assert {:ok, next} = Experiences.start(ctx.owner, ctx.world.id, next.id, 0)

    assert {:ok, %{actors: actors, items: items}} =
             Workspace.experience_view(ctx.owner, ctx.world.id, next.id)

    assert Enum.any?(actors, &(&1.id == "mara"))
    assert Enum.any?(items, &(&1.id == "mara-coin" and &1.quantity == 100))
  end
end
