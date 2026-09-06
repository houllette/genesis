defmodule Genesis.Persistence.Day103Test do
  use Genesis.DataCase, async: false
  import Genesis.WorldFixtures
  alias Genesis.Core.{Curation, Stock}
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}

  alias Genesis.Persistence.{
    Codec,
    Event,
    Experience,
    Preparation,
    PrepareTimeline,
    Seals,
    Snapshot,
    Snapshots,
    World
  }

  alias Genesis.{Campaigns, Content, Experiences, Workspace}

  test "day 100 Dock Crew spans three weekly gatherings; a two-hour courier overlaps and publication ends at day 103" do
    day100 = 100 * 86_400

    ctx =
      world_fixture(
        initial_time: day100,
        ruleset: "fantasy_local",
        transform: fn state ->
          {:ok, state} =
            Curation.apply(state, "mill", %{
              "kind" => "schedule",
              "name" => "Daily supply",
              "version" => 1,
              "first_at" => state.time.value + 86_400,
              "every" => %{"unit" => "day", "value" => 1},
              "actor_id" => "moll",
              "action" => "produce",
              "target_id" => "mill",
              "quantity" => 1
            })

          state
        end
      )

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara"
      )

    readings =
      start_supervised!({Agent, fn -> %{utc: ~U[2026-09-05 18:00:00.000000Z], monotonic: 0} end})

    clock = %{
      utc: fn -> Agent.get(readings, & &1.utc) end,
      monotonic: fn -> Agent.get(readings, & &1.monotonic) end
    }

    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: 0,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres,
       zone_opts: [clock: clock]}
    )

    {:ok, %{"zone_id" => depot}} =
      Content.create_zone(ctx.owner, ctx.world.id, %{"name" => "Courier depot"}, "depot")

    ctx = experience_fixture(ctx)
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, _} = Session.propose(session, "help", %{type: "help", target_id: "moll"})
    assert {:ok, _} = Session.confirm(session, "help", "help")

    {:ok, other} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "Conflicting mill visit", "zone_id" => "bridge"},
        "conflict"
      )

    assert {:error, :claimed} = Experiences.start(ctx.owner, ctx.world.id, other.id, 0)

    {:ok, courier} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "Two-hour courier", "zone_id" => depot},
        "courier"
      )

    {:ok, courier} = Experiences.start(ctx.owner, ctx.world.id, courier.id, 0)
    finish(ctx, courier, 7200)

    for week <- 1..3 do
      utc = Agent.get(readings, & &1.utc)

      assert {:ok, _} =
               Workspace.gather(
                 ctx.owner,
                 ctx.world.id,
                 ctx.experience.id,
                 %{"title" => "Gathering #{week}", "starts_at" => DateTime.to_iso8601(utc)},
                 "gather-#{week}"
               )

      seconds = if week == 1, do: 86_340, else: 86_400

      control(
        ctx,
        {:elapse,
         %{"unit" => "second", "value" => seconds, "reason" => "Day #{week} of the journey"}},
        "day-#{week}"
      )

      control(ctx, :pause, "pause-#{week}")

      Agent.update(
        readings,
        &%{utc: DateTime.add(&1.utc, 7 * 86_400), monotonic: &1.monotonic + 1_000}
      )

      assert Repo.get!(World, ctx.world.id).fictional_time == day100
      assert working(ctx).elapsed == week * 86_400
      control(ctx, :resume, "resume-#{week}")
    end

    Agent.update(readings, &%{&1 | utc: DateTime.add(&1.utc, -86_400)})
    finish(ctx, ctx.experience, 3 * 86_400)

    attrs = %{
      "decisions" =>
        Map.new(
          [ctx.experience, courier],
          &{&1.id, %{"mode" => "include", "reason" => "Outcomes reviewed"}}
        ),
      "downtime_seconds" => 0,
      "reason" => "Day 103 window"
    }

    assert {:ok, %{"preparation_id" => id}} =
             Runtime.call(ctx.owner, ctx.world.id, {:prepare_time, attrs, "prepare"})

    assert Repo.get!(World, ctx.world.id).fictional_time == day100

    assert :ok =
             perform_job(PrepareTimeline, %{
               "preparation_id" => id,
               "world_id" => ctx.world.id,
               "generation" => 0
             })

    assert Repo.get!(Preparation, id).status == "ready"
    assert {:ok, preview} = Runtime.call(ctx.owner, ctx.world.id, {:preview_time, id})

    assert {:ok, receipt} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert {:ok, ^receipt} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert Repo.get!(World, ctx.world.id).fictional_time == 103 * 86_400
    {:ok, published} = Snapshots.load(Repo.get!(Snapshot, ctx.published.id))
    assert Stock.balance(published, "moll", "grain") == 6
    assert Stock.balance(published, "moll", "ration") == 3
    assert published.actors["mara"].resources["effort"] == 9

    due =
      Repo.all(
        from e in Event,
          where:
            e.world_id == ^ctx.world.id and e.kind == "world" and like(e.core_event_id, "due-%"),
          order_by: e.cursor
      )

    assert Enum.map(due, &(Codec.load(&1.event) |> elem(1) |> Map.fetch!(:occurred_at))) ==
             Enum.map(101..103, &(&1 * 86_400))

    assert Enum.all?(due, &(not is_nil(&1.source_event_id)))
    assert length(Workspace.gatherings(ctx.owner, ctx.world.id, ctx.experience.id)) == 3
    next = experience_fixture(ctx, request_id: "next")
    {:ok, next_state} = Snapshots.load(next.snapshot)
    assert next_state.time.value == 103 * 86_400
    assert Stock.balance(next_state, "moll", "ration") == 3
  end

  defp working(ctx) do
    {:ok, state} = Snapshots.load(Repo.get!(Snapshot, ctx.snapshot.id))
    state
  end

  defp control(ctx, action, request),
    do:
      assert(
        {:ok, _} =
          Runtime.call(
            ctx.owner,
            ctx.world.id,
            {:status, ctx.experience.id, action, working(ctx).revision, request}
          )
      )

  defp finish(ctx, exp, seconds) do
    exp = Repo.get!(Experience, exp.id)
    {:ok, basis} = Seals.basis(exp)
    row = Repo.get_by!(Snapshot, experience_id: exp.id, zone_id: exp.zone_id)

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, exp.id,
                {:finish,
                 %{
                   "elapsed_seconds" => seconds,
                   "outcome" => "completed",
                   "reason" => "Finished",
                   "basis" => basis
                 }}, row.revision, "finish-#{exp.id}"}
             )
  end
end
