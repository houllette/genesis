defmodule Genesis.Persistence.TimelineReviewTest do
  use Genesis.DataCase, async: false
  import Genesis.WorldFixtures
  alias Genesis.Core.{Curation, Stock}
  alias Genesis.Engine.{Runtime, WorldSupervisor}

  alias Genesis.Persistence.{
    Claim,
    Event,
    Experience,
    LocalTime,
    Preparation,
    PrepareTimeline,
    Seals,
    Snapshot,
    Snapshots,
    World
  }

  alias Genesis.{Content, Experiences, Workspace}

  @moduletag capture_log: true

  for stage <- [
        :publication_after_prepare,
        :before_commit,
        :after_commit,
        :publication_after_first_install,
        :after_install
      ] do
    @tag stage: stage
    test "timed snapshots, dates, claims and receipt recover together at #{stage}", %{
      stage: stage
    } do
      ctx = world_fixture(ruleset: "fantasy_local", transform: &scheduled/1)
      pid = start_owner(ctx)

      {:ok, %{"zone_id" => other}} =
        Content.create_zone(ctx.owner, ctx.world.id, %{"name" => "Other place"}, "other")

      ctx = experience_fixture(ctx)
      finish(ctx, 180)
      id = prepare(ctx, "include", 0)
      run_job(ctx, id)
      assert {:ok, preview} = Runtime.call(ctx.owner, ctx.world.id, {:preview_time, id})
      fault = fn point -> if point == stage, do: exit(:injected_failure), else: :ok end
      :sys.replace_state(pid, &%{&1 | zone_opts: [fault: fault]})

      assert {:error, :publication_interrupted} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      expected = if stage in [:publication_after_prepare, :before_commit], do: 0, else: 180
      assert Repo.get!(World, ctx.world.id).fictional_time == expected
      :sys.replace_state(pid, &%{&1 | zone_opts: []})

      assert {:ok, receipt} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert {:ok, ^receipt} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert published(ctx).time.value == 180
      assert {:ok, other_view} = Content.view(ctx.owner, ctx.world.id, other)
      assert other_view.time.value == 180
      assert Stock.balance(published(ctx), "moll", "ration") == 3
      assert Repo.get!(Experience, ctx.experience.id).status == "incorporated"
      refute Repo.exists?(from c in Claim, where: c.experience_id == ^ctx.experience.id)

      assert Repo.aggregate(
               from(e in Event,
                 where:
                   e.world_id == ^ctx.world.id and e.kind == "world" and
                     like(e.core_event_id, "due-%")
               ),
               :count
             ) == 3
    end
  end

  test "preparation survives World restart, and a failed batch leaves its durable cursor unchanged" do
    ctx = world_fixture(ruleset: "fantasy_local", transform: &scheduled/1) |> experience_fixture()
    pid = start_owner(ctx)
    finish(ctx, 2400)
    id = prepare(ctx, "include", 0)
    before = Repo.get!(Preparation, id)

    fault = fn stage ->
      if stage == :preparation_before_commit, do: exit(:injected_failure), else: :ok
    end

    :sys.replace_state(pid, &%{&1 | zone_opts: [fault: fault]})
    ref = Process.monitor(pid)
    assert catch_exit(Runtime.call(ctx.owner, ctx.world.id, {:step_time, id, 0}))
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2000
    assert_receive {:genesis_world_started, _next}, 2000
    assert Repo.get!(Preparation, id).digest == before.digest
    run_job(ctx, id)
    assert Repo.get!(Preparation, id).status == "preparing"
    assert :ok = stop_supervised(WorldSupervisor)
    start_owner(ctx)
    run_job(ctx, id)
    assert Repo.get!(Preparation, id).status == "ready"
    assert Repo.get!(World, ctx.world.id).fictional_time == 0
    publish(ctx, id)
    assert published(ctx).time.value == 2400
  end

  test "start offsets run due effects before play without counting the offset as adventure duration" do
    ctx =
      world_fixture(ruleset: "fantasy_local", transform: &scheduled/1)
      |> experience_fixture(start_offset: 120)

    start_owner(ctx)
    assert {:ok, state} = Snapshots.load(Repo.get!(Snapshot, ctx.snapshot.id))
    assert {state.time.value, state.elapsed} == {120, 0}
    assert Stock.balance(state, "moll", "ration") == 2
    assert {:ok, summary} = LocalTime.summary(ctx.experience)
    assert summary.elapsed_seconds == 0
    finish(ctx, 60)
    id = prepare(ctx, "include", 0)
    run_job(ctx, id)
    assert Repo.get!(Preparation, id).status == "ready"
    assert Repo.get!(Preparation, id).manifest["target"] == 180
    publish(ctx, id)
    assert {published(ctx).time.value, published(ctx).elapsed} == {180, 0}
    assert Stock.balance(published(ctx), "moll", "ration") == 3

    assert Repo.aggregate(
             from(e in Event,
               where:
                 e.world_id == ^ctx.world.id and e.kind == "world" and
                   like(e.core_event_id, "due-%")
             ),
             :count
           ) == 3
  end

  test "all excluded outcomes retain records and release claims without advancing or exporting rewards" do
    ctx = world_fixture(ruleset: "fantasy_local", transform: &scheduled/1) |> experience_fixture()
    start_owner(ctx)

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id,
                {:elapse, %{"unit" => "minute", "value" => 2, "reason" => "Unpublished milling"}},
                0, "local"}
             )

    finish(ctx, 120)
    completion = Repo.get!(Experience, ctx.experience.id).completion
    id = prepare(ctx, "exclude", 0)
    run_job(ctx, id)
    publish(ctx, id)
    assert Repo.get!(World, ctx.world.id).fictional_time == 0
    assert Repo.get!(Experience, ctx.experience.id).status == "closed_without_publication"
    assert Repo.get!(Experience, ctx.experience.id).completion == completion
    refute Repo.exists?(from c in Claim, where: c.experience_id == ^ctx.experience.id)
    assert Stock.balance(published(ctx), "moll", "ration") == 0
    assert {:error, _} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    assert {:ok, review} = Workspace.experience_review(ctx.owner, ctx.world.id, ctx.experience.id)
    assert review.elapsed_seconds == 120
    next = experience_fixture(ctx, request_id: "next")
    assert {:ok, working} = Snapshots.load(next.snapshot)
    assert Stock.balance(working, "moll", "ration") == 0
  end

  test "downtime alone is bounded and resumable; sealed windows fence admission and curation" do
    ctx = world_fixture(ruleset: "fantasy_local", transform: &scheduled/1)
    start_owner(ctx)

    attrs = %{
      "decisions" => %{},
      "downtime_seconds" => 2400,
      "reason" => "Approved quiet interval"
    }

    assert {:ok, %{"preparation_id" => id}} =
             Runtime.call(ctx.owner, ctx.world.id, {:prepare_time, attrs, "downtime"})

    assert {:error, _} = Runtime.call(ctx.owner, ctx.world.id, {:preview_time, id})
    run_job(ctx, id)
    assert Repo.get!(Preparation, id).status == "preparing"
    assert Repo.get!(World, ctx.world.id).fictional_time == 0
    assert_enqueued(worker: PrepareTimeline, args: %{preparation_id: id})
    run_job(ctx, id)
    assert Repo.get!(Preparation, id).status == "ready"

    assert {:ok, exp} =
             Experiences.create(
               ctx.owner,
               ctx.world.id,
               ctx.campaign.id,
               %{"name" => "Too late", "zone_id" => "bridge"},
               "late"
             )

    assert {:error, _} = Experiences.start(ctx.owner, ctx.world.id, exp.id, 0)

    assert {:ok, %{"status" => "draft"}} =
             Content.curate(
               ctx.owner,
               ctx.world.id,
               "bridge",
               ctx.published.revision,
               nil,
               %{"kind" => "npc", "name" => "Deferred newcomer"},
               "edit"
             )

    publish(ctx, id)
    assert Repo.get!(World, ctx.world.id).fictional_time == 2400
    assert Stock.balance(published(ctx), "moll", "ration") == 6
    run_job(ctx, id)
  end

  test "cancellation and revised totals preserve completion and invalidate the old confirmation" do
    ctx = world_fixture() |> experience_fixture()
    start_owner(ctx)
    finish(ctx, 7200)
    original = Repo.get!(Experience, ctx.experience.id).completion
    id = prepare(ctx, "include", 0)
    run_job(ctx, id)
    assert {:ok, preview} = Runtime.call(ctx.owner, ctx.world.id, {:preview_time, id})
    row = Repo.get!(Preparation, id)

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:cancel_time, id, row.digest, "Correct the unrecorded total"}
             )

    assert {:error, _} = Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "old"})
    run_job(ctx, id)

    attrs = %{
      "decisions" => %{
        ctx.experience.id => %{
          "mode" => "include",
          "reason" => "Corrected total",
          "elapsed_seconds" => 3600
        }
      },
      "downtime_seconds" => 0,
      "reason" => "Review again"
    }

    assert {:ok, %{"preparation_id" => revised}} =
             Runtime.call(ctx.owner, ctx.world.id, {:prepare_time, attrs, "revised"})

    run_job(ctx, revised)
    publish(ctx, revised)
    assert Repo.get!(World, ctx.world.id).fictional_time == 3600
    assert Repo.get!(Experience, ctx.experience.id).completion == original
  end

  defp scheduled(state) do
    {:ok, state} =
      Curation.apply(state, "mill", %{
        "kind" => "schedule",
        "name" => "Milling",
        "version" => 1,
        "first_at" => state.time.value + 60,
        "every" => %{"unit" => "minute", "value" => 1},
        "actor_id" => "moll",
        "action" => "produce",
        "target_id" => "mill",
        "quantity" => 1
      })

    state
  end

  defp start_owner(ctx) do
    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: 0,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres,
       observer: self()}
    )

    assert_receive {:genesis_world_started, pid}, 2000
    pid
  end

  defp finish(ctx, seconds) do
    exp = Repo.get!(Experience, ctx.experience.id)
    {:ok, basis} = Seals.basis(exp)
    revision = Repo.get_by!(Snapshot, experience_id: exp.id, zone_id: exp.zone_id).revision

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, exp.id,
                {:finish,
                 %{
                   "elapsed_seconds" => seconds,
                   "outcome" => "completed",
                   "reason" => "The errand is finished",
                   "basis" => basis
                 }}, revision, "finish"}
             )
  end

  defp prepare(ctx, mode, downtime) do
    attrs = %{
      "decisions" => %{
        ctx.experience.id => %{"mode" => mode, "reason" => "Reviewed actual outcomes"}
      },
      "downtime_seconds" => downtime,
      "reason" => "Reviewed window"
    }

    assert {:ok, %{"preparation_id" => id}} =
             Runtime.call(ctx.owner, ctx.world.id, {:prepare_time, attrs, "prepare"})

    id
  end

  defp run_job(ctx, id),
    do:
      assert(
        :ok ==
          perform_job(PrepareTimeline, %{
            "preparation_id" => id,
            "world_id" => ctx.world.id,
            "generation" => 0
          })
      )

  defp publish(ctx, id) do
    assert {:ok, preview} = Runtime.call(ctx.owner, ctx.world.id, {:preview_time, id})
    assert {:ok, _} = Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})
  end

  defp published(ctx) do
    assert {:ok, state} = Snapshots.load(Repo.get!(Snapshot, ctx.published.id))
    state
  end
end
