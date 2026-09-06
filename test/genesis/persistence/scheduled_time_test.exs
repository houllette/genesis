defmodule Genesis.Persistence.ScheduledTimeTest do
  use Genesis.DataCase, async: false
  import Genesis.WorldFixtures
  alias Genesis.Core.{Curation, Stock}
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}

  alias Genesis.Persistence.{
    Checkpoint,
    Codec,
    Event,
    Experience,
    PrepareTimeline,
    Replay,
    Seals,
    Snapshot,
    Snapshots,
    World
  }

  test "paid action durations resolve due points without charging the action twice" do
    ctx =
      world_fixture(
        ruleset: "fantasy_local",
        transform: fn state ->
          {:ok, state} =
            Curation.apply(state, "mill", %{
              "kind" => "schedule",
              "name" => "Busy milling",
              "version" => 1,
              "first_at" => 30,
              "every" => %{"unit" => "second", "value" => 30},
              "actor_id" => "moll",
              "action" => "produce",
              "target_id" => "mill",
              "quantity" => 1
            })

          state
        end
      )

    {:ok, _} =
      Genesis.Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara"
      )

    ctx = experience_fixture(ctx)

    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: 0,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres}
    )

    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, _} = Session.propose(session, "help", %{type: "help", target_id: "moll"})
    assert {:ok, receipt} = Session.confirm(session, "help", "help")
    assert {:ok, ^receipt} = Session.confirm(session, "help", "help")
    assert {:ok, state} = Snapshots.load(Repo.get!(Snapshot, ctx.snapshot.id))
    assert state.elapsed == 60
    assert state.actors["mara"].resources["effort"] == 9
    assert Stock.balance(state, "moll", "ration") == 2

    cp =
      Repo.one!(
        from c in Checkpoint,
          where: c.snapshot_id == ^ctx.snapshot.id,
          order_by: c.cursor,
          limit: 1
      )

    assert Replay.restore(ctx.owner, ctx.world.id, cp.id) == {:ok, state}
    {:ok, basis} = Seals.basis(Repo.get!(Experience, ctx.experience.id))

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id,
                {:finish,
                 %{
                   "elapsed_seconds" => 60,
                   "outcome" => "completed",
                   "reason" => "Finished",
                   "basis" => basis
                 }}, state.revision, "finish"}
             )

    attrs = %{
      "decisions" => %{ctx.experience.id => %{"mode" => "include", "reason" => "Reviewed"}},
      "downtime_seconds" => 0,
      "reason" => "Publish"
    }

    assert {:ok, %{"preparation_id" => id}} =
             Runtime.call(ctx.owner, ctx.world.id, {:prepare_time, attrs, "prepare"})

    assert :ok =
             perform_job(PrepareTimeline, %{
               "preparation_id" => id,
               "world_id" => ctx.world.id,
               "generation" => 0
             })

    assert {:ok, preview} = Runtime.call(ctx.owner, ctx.world.id, {:preview_time, id})
    assert {:ok, _} = Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})
    assert {:ok, published} = Snapshots.load(Repo.get!(Snapshot, ctx.published.id))
    assert published.time.value == 60
    assert Stock.balance(published, "moll", "ration") == 2
  end

  test "scene advancement saves individually dated effects and recovers an exact retry" do
    ctx =
      world_fixture(
        ruleset: "fantasy_local",
        transform: fn state ->
          {:ok, state} =
            Curation.apply(state, "mill", %{
              "kind" => "schedule",
              "name" => "Daily milling",
              "version" => 1,
              "first_at" => 60,
              "every" => %{"unit" => "minute", "value" => 1},
              "actor_id" => "moll",
              "action" => "produce",
              "target_id" => "mill",
              "quantity" => 1
            })

          state
        end
      )
      |> experience_fixture()

    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: ctx.world.generation,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres}
    )

    command =
      {:status, ctx.experience.id,
       {:elapse, %{"unit" => "minute", "value" => 3, "reason" => "An afternoon at the mill"}}, 0,
       "afternoon"}

    assert {:ok, result} = Runtime.call(ctx.owner, ctx.world.id, command)
    assert {:ok, ^result} = Runtime.call(ctx.owner, ctx.world.id, command)
    row = Repo.get!(Snapshot, ctx.snapshot.id)
    assert {:ok, state} = Snapshots.load(row)
    assert Stock.balance(state, "moll", "grain") == 6
    assert Stock.balance(state, "moll", "ration") == 3
    assert state.time.value == 180
    assert Repo.get!(World, ctx.world.id).fictional_time == 0

    checkpoint =
      Repo.one!(
        from c in Checkpoint, where: c.snapshot_id == ^row.id, order_by: c.cursor, limit: 1
      )

    assert Replay.restore(ctx.owner, ctx.world.id, checkpoint.id) == {:ok, state}

    dated =
      Repo.all(from e in Event, where: e.experience_id == ^ctx.experience.id, order_by: e.cursor)
      |> Enum.map(&(Codec.load(&1.event) |> elem(1)))
      |> Enum.filter(&Map.has_key?(&1, :schedule_id))

    assert Enum.map(dated, & &1.occurred_at) == [60, 120, 180]
    assert Enum.sum(Enum.map(dated, & &1.time["seconds"])) == 180
  end

  test "due effects never draw a second roll for an already confirmed check" do
    ctx =
      world_fixture(
        transform: fn state ->
          {:ok, state} =
            Curation.apply(state, "season", %{
              "kind" => "schedule",
              "name" => "Season starts",
              "version" => 1,
              "first_at" => 15,
              "action" => "condition",
              "condition" => "harsh"
            })

          state
        end
      )

    {:ok, _} =
      Genesis.Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara"
      )

    ctx = experience_fixture(ctx)
    counter = start_supervised!({Agent, fn -> 0 end})

    draw = fn _check ->
      Agent.update(counter, &(&1 + 1))
      [20]
    end

    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: 0,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres,
       zone_opts: [draw: draw]}
    )

    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    assert {:ok, _} = Session.propose(session, "attempt", %{type: "attempt", target_id: "moll"})
    assert {:ok, receipt} = Session.confirm(session, "attempt", "attempt")
    assert {:ok, ^receipt} = Session.confirm(session, "attempt", "attempt")
    assert Agent.get(counter, & &1) == 1
    {:ok, state} = Snapshots.load(Repo.get!(Snapshot, ctx.snapshot.id))
    assert state.elapsed == 30
    assert state.actors["mara"].resources["effort"] == 9
    assert state.timeline["condition"] == "harsh"
  end
end
