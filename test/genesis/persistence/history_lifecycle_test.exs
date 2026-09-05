defmodule Genesis.Persistence.HistoryLifecycleTest do
  use Genesis.DataCase, async: false
  alias Genesis.Accounts.Scope
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}

  alias Genesis.Persistence.{
    Checkpoint,
    Claim,
    Experience,
    History,
    Replay,
    Snapshot,
    Snapshots,
    Tx
  }

  alias Genesis.Campaigns
  alias Genesis.Time.Deadline
  import Genesis.AccountsFixtures
  import Genesis.WorldFixtures

  test "pause, real weeks and World restart preserve fictional time and saved deadline remainder" do
    ctx = world_fixture()

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara"
      )

    ctx = experience_fixture(ctx)
    pin = ~U[2026-09-04 12:00:00.123456Z]
    clock_state = start_supervised!({Agent, fn -> %{utc: pin, mono: 100} end})

    clock = %{
      utc: fn -> Agent.get(clock_state, & &1.utc) end,
      monotonic: fn -> Agent.get(clock_state, & &1.mono) end
    }

    tree(ctx, clock: clock)

    Tx.update!(ctx.experience, %{
      deadline: %{
        "format" => 1,
        "remaining_ms" => 5000,
        "paused" => false,
        "deadline_at" => pin |> DateTime.add(5) |> DateTime.to_iso8601()
      }
    })

    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, _} = Session.propose(session, "help", %{type: "help", target_id: "moll"})
    {:ok, _} = Session.confirm(session, "help", "help")

    assert {:ok, %{"status" => "paused"}} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, :pause, 1, "pause"}
             )

    assert {:ok, %{status: :paused, elapsed: 60}} = Session.view(session)
    exp = Repo.get!(Experience, ctx.experience.id)
    assert exp.deadline["remaining_ms"] == 5000
    Agent.update(clock_state, &%{&1 | utc: DateTime.add(pin, 21, :day), mono: 900})

    world =
      GenServer.whereis(
        Genesis.Engine.Supervisor.via(Genesis.Engine.Registry, {:world, ctx.world.id})
      )

    monitor = Process.monitor(world)
    Process.exit(world, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^world, :killed}

    assert {:ok, %{"status" => "active"}} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, :resume, 2, "resume"}
             )

    {:ok, fresh} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    assert {:ok, %{elapsed: 60, revision: 3}} = Session.view(fresh)
    assert Repo.get!(Experience, exp.id).deadline["remaining_ms"] == 5000
    assert Repo.aggregate(from(c in Claim, where: c.experience_id == ^exp.id), :count) == 7
    checkpoint = Repo.get_by!(Checkpoint, snapshot_id: ctx.snapshot.id)
    assert {:ok, replayed} = Replay.restore(ctx.owner, ctx.world.id, checkpoint.id)

    assert {:ok, ^replayed} =
             ctx.snapshot.id |> then(&Repo.get!(Snapshot, &1)) |> Snapshots.load()

    assert {:ok, page} = History.page(ctx.owner, ctx.world.id, experience_id: exp.id)
    assert Enum.find(page.events, &(&1.type == "help")).recorded_at == pin
  end

  test "history filters before paging, freezes recipients, and revocation blocks replay of receipts" do
    ctx = world_fixture(private_target: true)
    player = Scope.for_user(user_fixture())

    {:ok, _} =
      Campaigns.add_member(ctx.owner, ctx.world.id, ctx.campaign.id, player.user.id, "player")

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        player.user.id,
        "courier"
      )

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara"
      )

    ctx = experience_fixture(ctx, participants: ["mara", "courier"])
    tree(ctx)
    {:ok, gm} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, courier} = Runtime.attach(player, ctx.world.id, ctx.experience.id, "courier")
    {:ok, _} = Session.propose(gm, "whisper", %{type: "help", target_id: "moll"})
    {:ok, _} = Session.confirm(gm, "whisper", "whisper")

    assert {:ok, %{events: []}} =
             History.page(player, ctx.world.id, experience_id: ctx.experience.id, limit: 1)

    assert {:ok, _} =
             Session.submit(courier, %{
               id: "take",
               revision: 1,
               intent: %{type: "take", target_id: "ration"}
             })

    assert {:ok, %{events: [event], next_cursor: cursor}} =
             History.page(player, ctx.world.id, experience_id: ctx.experience.id, limit: 1)

    assert event.type == "take"
    refute Map.has_key?(event, :source_ids)

    assert {:ok, %{events: []}} =
             History.page(player, ctx.world.id, experience_id: ctx.experience.id, after: cursor)

    late = Scope.for_user(user_fixture())
    {:ok, _} = Campaigns.add_member(ctx.owner, ctx.world.id, ctx.campaign.id, late.user.id, "gm")

    assert {:ok, %{events: []}} =
             History.page(late, ctx.world.id, experience_id: ctx.experience.id)

    {:ok, _} = Campaigns.revoke_member(ctx.owner, ctx.world.id, ctx.campaign.id, player.user.id)

    assert {:error, :unauthorized} =
             Session.submit(courier, %{
               id: "take",
               revision: 1,
               intent: %{type: "take", target_id: "ration"}
             })

    assert {:error, :unauthorized} =
             History.page(player, ctx.world.id, experience_id: ctx.experience.id)

    assert {:error, :unauthorized} =
             Runtime.attach(player, ctx.world.id, ctx.experience.id, "courier")
  end

  test "backward real clock is capped by saved remainder, never a prior VM's monotonic counter" do
    saved = %{
      "format" => 1,
      "remaining_ms" => 2000,
      "paused" => false,
      "deadline_at" => "2026-09-04T12:00:02Z"
    }

    clock = %{utc: fn -> ~U[2026-09-03 12:00:00Z] end, monotonic: fn -> -5000 end}

    assert {:ok, %{remaining_ms: 2000, monotonic_deadline_ms: -3000}} =
             Deadline.recover(saved, clock)

    assert {:error, :invalid_deadline} =
             Deadline.recover(Map.put(saved, "monotonic", 100), clock)
  end

  defp tree(ctx, opts \\ []),
    do:
      start_supervised!(
        {WorldSupervisor,
         world_id: ctx.world.id,
         generation: ctx.world.generation,
         registry: Genesis.Engine.Registry,
         owner: self(),
         storage: :postgres,
         zone_opts: opts}
      )
end
