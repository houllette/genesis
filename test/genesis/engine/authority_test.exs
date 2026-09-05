defmodule Genesis.Engine.AuthorityTest do
  use ExUnit.Case, async: true
  import Genesis.SceneFixtures
  alias Genesis.Core.Scope
  alias Genesis.Engine.{Session, World, Zone}
  alias Genesis.Engine.Supervisor, as: Engine
  alias Genesis.Systems
  alias Tempo.Clock, as: TempoClock
  alias Tempo.Clock.Test, as: TestClock

  setup do
    start_supervised!(
      {Engine, name: __MODULE__.Engine, registry: __MODULE__.Registry, worlds: __MODULE__.Worlds}
    )

    {:ok, world} =
      Engine.start_world(__MODULE__.Registry, __MODULE__.Worlds,
        world_id: "ashfall",
        generation: 0,
        observer: self()
      )

    assert_receive {:genesis_world_started, ^world}

    scene = scene()
    {:ok, zone} = World.admit(world, scene)
    %{world: world, zone: zone, scene: scene}
  end

  test "only trusted grants create attachments; direct calls and forged payloads cannot grant roles",
       ctx do
    token = grant(ctx, "mara")
    {:ok, session} = World.attach(ctx.world, token, ctx.zone)
    assert {:ok, view} = Session.view(session)
    assert Enum.map(view.items, & &1.id) == ["ration"]
    refute inspect(view) =~ "sealed-letter"
    assert {:error, :unauthorized} = Zone.view(ctx.zone)
    assert {:error, :unauthorized} = World.attach(ctx.world, make_ref(), ctx.zone)
    request = request("take-1", 0)
    assert {:error, :invalid_request} = Session.submit(session, Map.put(request, :role, :gm))

    assert {:error, :invalid_request} =
             Session.submit(
               session,
               put_in(request.intent, %{type: "take", target_id: "ration", actor_id: "courier"})
             )

    assert {:error, :unavailable} =
             Session.submit(session, put_in(request.intent.target_id, "sealed-letter"))

    tasks = start_supervised!(Task.Supervisor)

    forged =
      Task.Supervisor.async_nolink(tasks, fn ->
        World.grant(ctx.world, principal(ctx, "mara", :gm))
      end)

    assert {:error, :unauthorized} = Task.await(forged)
    spectator = grant(ctx, "courier", :spectator)
    {:ok, watching} = World.attach(ctx.world, spectator, ctx.zone)
    assert {:ok, _} = Session.view(watching)
    assert {:error, :read_only} = Session.submit(watching, request)
  end

  test "barrier-released sessions contend for one item with one accepted revision", ctx do
    tokens = Enum.map(["mara", "courier"], &grant(ctx, &1))
    task_supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    tasks =
      Enum.map(tokens, fn token ->
        Task.Supervisor.async_nolink(task_supervisor, fn ->
          {:ok, session} = World.attach(ctx.world, token, ctx.zone)
          {:ok, view} = Session.view(session)
          send(parent, {:ready, self()})

          receive do
            :go -> Session.submit(session, request("contested", view.revision))
          end
        end)
      end)

    for _ <- 1..2, do: assert_receive({:ready, _pid})
    Enum.each(tasks, &send(&1.pid, :go))
    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :stale_revision})) == 1
    token = grant(ctx, "mara", :gm)
    {:ok, session} = World.attach(ctx.world, token, ctx.zone)
    {:ok, view} = Session.view(session)
    assert view.revision == 1

    assert [%{owner: {:actor, owner}, quantity: 2}] =
             Enum.filter(view.items, &(&1.id == "ration"))

    assert owner in ["mara", "courier"]
  end

  test "receipts bind payload and principal; lost notification resync is safe", ctx do
    {:ok, session} = World.attach(ctx.world, grant(ctx, "mara"), ctx.zone)
    {:ok, _view} = Session.view(session)
    request = request("once", 0)
    assert {:ok, result} = Session.submit(session, request)
    assert result.durability == :ephemeral
    assert {:ok, ^result} = Session.submit(session, request)
    assert {:error, :request_id_reused} = Session.submit(session, %{request | revision: 1})
    assert_receive {:genesis_changed, ^session}
    send(session, {:zone_changed, ctx.zone})
    assert {:ok, resynced} = Session.view(session)
    assert resynced.revision == 1
    assert Enum.find(resynced.items, &(&1.id == "ration")).owner == {:actor, "mara"}
    refute inspect(:sys.get_state(session)) =~ "sealed-letter"
    refute Map.has_key?(:sys.get_state(session), :scene)
  end

  test "claims and one window survive pause and last detach; rehearsal stays isolated", ctx do
    second = %{ctx.scene | scope: %{ctx.scene.scope | id: "courier-run"}}
    assert {:error, :claimed} = World.admit(ctx.world, second)

    assert {:error, :invalid_scope} =
             World.admit(ctx.world, %{
               second
               | scope: %{second.scope | window_id: "another-window"}
             })

    assert {:error, :invalid_scope} = World.admit(ctx.world, second, start_offset: 1)

    rehearsal = %{
      ctx.scene
      | scope: %{ctx.scene.scope | kind: :rehearsal, window_id: nil, id: "preview"}
    }

    assert {:ok, preview_zone} = World.admit(ctx.world, rehearsal)
    refute preview_zone == ctx.zone
    {:ok, session} = World.attach(ctx.world, grant(ctx, "mara"), ctx.zone)
    {:ok, initial} = Session.view(session)
    assert :ok = World.pause(ctx.world, ctx.scene.scope)
    assert {:error, :paused} = Session.submit(session, request("paused", initial.revision))
    {:ok, paused} = Session.view(session)
    assert paused.time == initial.time
    assert paused.status == :paused
    assert :ok = Session.detach(session)
    assert {:error, :claimed} = World.admit(ctx.world, second)
    assert :ok = World.resume(ctx.world, ctx.scene.scope)
    {:ok, resumed_session} = World.attach(ctx.world, grant(ctx, "mara"), ctx.zone)
    {:ok, resumed} = Session.view(resumed_session)
    assert resumed.time == initial.time
    assert resumed.elapsed == 0
  end

  test "two connections share an actor; an old detach cannot disconnect its new attachment",
       ctx do
    token = grant(ctx, "mara")
    {:ok, first} = World.attach(ctx.world, token, ctx.zone)
    {:ok, second} = World.attach(ctx.world, token, ctx.zone)
    assert {:ok, _} = Session.view(first)
    assert {:ok, _} = Session.view(second)
    assert :ok = Session.detach(first)
    {:ok, view} = Session.view(second)
    refute "mara" in view.disconnected
    {:ok, observer} = World.attach(ctx.world, grant(ctx, "courier"), ctx.zone)
    {:ok, _} = Session.view(observer)
    assert :ok = Session.detach(second)
    {:ok, view} = Session.view(observer)
    assert "mara" in view.disconnected
    {:ok, third} = World.attach(ctx.world, token, ctx.zone)
    {:ok, _} = Session.view(third)
    send(ctx.zone, {:DOWN, make_ref(), :process, second, :normal})
    {:ok, view} = Session.view(observer)
    refute "mara" in view.disconnected
  end

  test "confirmation uses current server context and revocation fences even stored receipts",
       ctx do
    token = grant(ctx, "mara")
    {:ok, session} = World.attach(ctx.world, token, ctx.zone)
    assert {:clarify, :target_id} = Session.propose(session, "clarify", %{type: "access"})

    assert {:ok, proposal} =
             Session.propose(session, "access", %{type: "access", target_id: "moll"})

    assert proposal.terms["cost"] == 2
    refute inspect(proposal) =~ "friendship"

    assert {:error, :invalid_request} =
             Session.propose(session, "forge", %{
               type: "access",
               target_id: "moll",
               history: "rescuer"
             })

    assert {:ok, _help} = Session.propose(session, "help", %{type: "help", target_id: "moll"})
    assert {:ok, _} = Session.confirm(session, "help-request", "help")
    assert {:error, :stale_proposal} = Session.confirm(session, "access-request", "access")
    assert {:ok, _fresh} = Session.propose(session, "fresh", %{type: "access", target_id: "moll"})

    assert {:ok, %{effects: [%{result: %{"outcome" => "admitted"}}]}} =
             Session.confirm(session, "fresh-request", "fresh")

    monitor = Process.monitor(session)
    assert :ok = World.revoke(ctx.world, token)
    assert {:error, :unauthorized} = World.authorize(ctx.world, token, ctx.scene.scope, "bridge")
    assert_receive {:genesis_revoked, ^session}
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}
  end

  test "zone crash fails closed and retains claims; world crash fences all old attachments",
       ctx do
    token = grant(ctx, "mara")
    {:ok, session} = World.attach(ctx.world, token, ctx.zone)
    assert {:ok, _} = Session.submit(session, request("taken", 0))
    zone_monitor = Process.monitor(ctx.zone)
    session_monitor = Process.monitor(session)
    Process.exit(ctx.zone, :kill)
    assert_receive {:DOWN, ^zone_monitor, :process, _, :killed}
    assert_receive {:DOWN, ^session_monitor, :process, _, :normal}
    _ = :sys.get_state(ctx.world)
    assert {:error, :state_lost} = World.admit(ctx.world, ctx.scene)

    assert {:error, :claimed} =
             World.admit(ctx.world, %{ctx.scene | scope: %{ctx.scene.scope | id: "another"}})

    assert {:ok, _same_world} =
             Engine.start_world(__MODULE__.Registry, __MODULE__.Worlds,
               world_id: "ashfall",
               generation: 0
             )
  end

  test "even the same experience cannot seed a second spendable copy in another zone", ctx do
    copied = %{ctx.scene | zone_id: "market"}
    assert {:error, :claimed} = World.admit(ctx.world, copied)
  end

  test "starting a new generation cannot create a competing authority for an active world", ctx do
    assert {:error, :generation_mismatch} =
             Engine.start_world(__MODULE__.Registry, __MODULE__.Worlds,
               world_id: "ashfall",
               generation: 99
             )

    assert {:ok, ctx.world} ==
             Engine.start_world(__MODULE__.Registry, __MODULE__.Worlds,
               world_id: "ashfall",
               generation: 0
             )
  end

  test "a receipt cannot be replayed under a different campaign binding", ctx do
    first = principal(ctx, "mara", :player)
    {:ok, token} = World.grant(ctx.world, first)
    {:ok, session} = World.attach(ctx.world, token, ctx.zone)
    assert {:ok, _result} = Session.submit(session, request("bound", 0))
    {:ok, other_token} = World.grant(ctx.world, %{first | campaign_id: "different-campaign"})
    {:ok, other} = World.attach(ctx.world, other_token, ctx.zone)
    assert {:error, :request_id_reused} = Session.submit(other, request("bound", 0))
  end

  test "world restart destroys ephemeral state and old grants, and disconnects dependent sessions",
       ctx do
    token = grant(ctx, "mara")
    {:ok, session} = World.attach(ctx.world, token, ctx.zone)
    assert {:ok, _} = Session.submit(session, request("before-restart", 0))
    old_world = ctx.world
    world_monitor = Process.monitor(old_world)
    session_monitor = Process.monitor(session)
    zone_monitor = Process.monitor(ctx.zone)
    Process.exit(old_world, :kill)
    assert_receive {:DOWN, ^world_monitor, :process, ^old_world, :killed}
    assert_receive {:genesis_world_started, new_world}
    assert_receive {:DOWN, ^session_monitor, :process, ^session, _reason}
    assert_receive {:DOWN, ^zone_monitor, :process, _zone, _reason}
    refute new_world == old_world
    assert {:error, :unauthorized} = World.authorize(new_world, token, ctx.scene.scope, "bridge")
    assert :sys.get_state(new_world).claims == %{}
    assert :sys.get_state(new_world).zones == %{}
  end

  test "an independent session crash preserves zone state and allows a fresh attachment", ctx do
    token = grant(ctx, "mara")
    {:ok, session} = World.attach(ctx.world, token, ctx.zone)
    assert {:ok, result} = Session.submit(session, request("before-session-crash", 0))
    monitor = Process.monitor(session)
    Process.exit(session, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^session, :killed}
    {:ok, replacement} = World.attach(ctx.world, token, ctx.zone)
    assert {:ok, view} = Session.view(replacement)
    assert view.items == result.view.items
    assert view.revision == result.revision
    refute "mara" in view.disconnected
    assert {:ok, ctx.zone} == World.admit(ctx.world, ctx.scene)
    assert {:ok, retried} = Session.submit(replacement, request("before-session-crash", 0))
    assert retried.effects == result.effects
  end

  test "slow readers receive a single safe invalidation and resync to the latest state", ctx do
    {:ok, acting} = World.attach(ctx.world, grant(ctx, "mara"), ctx.zone)
    {:ok, observing} = World.attach(ctx.world, grant(ctx, "courier", :spectator), ctx.zone)
    {:ok, _} = Session.view(observing)

    for index <- 1..3 do
      id = "help-#{index}"
      assert {:ok, _} = Session.propose(acting, id, %{type: "help", target_id: "moll"})
      assert {:ok, _} = Session.confirm(acting, id, id)
    end

    assert_receive {:genesis_changed, ^observing}
    refute_receive {:genesis_changed, ^observing}
    assert {:ok, view} = Session.view(observing)
    assert view.revision == 3
    assert view.elapsed == 180
    refute inspect(view) =~ "secret-source"
    refute Map.has_key?(:sys.get_state(observing), :events)
  end

  test "registry rejects competing zone writers and isolates matching IDs in another world",
       ctx do
    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    zone_name =
      Engine.via(
        __MODULE__.Registry,
        {:zone, {Scope.key(ctx.scene.scope), "bridge"}}
      )

    attempts =
      for _ <- 1..2 do
        Task.Supervisor.async_nolink(supervisor, fn ->
          send(parent, {:writer_ready, self()})

          receive do
            :go -> Zone.start_link(name: zone_name, world: ctx.world, scene: ctx.scene)
          end
        end)
      end

    for _ <- attempts, do: assert_receive({:writer_ready, _pid})
    Enum.each(attempts, &send(&1.pid, :go))

    for attempt <- attempts,
        do: assert({:error, {:already_started, ctx.zone}} == Task.await(attempt))

    {:ok, other_world} =
      Engine.start_world(__MODULE__.Registry, __MODULE__.Worlds, world_id: "other", generation: 0)

    other_scope = %{ctx.scene.scope | world_id: "other"}

    other_scene = %{
      ctx.scene
      | scope: other_scope,
        time: %{ctx.scene.time | world_id: "other"},
        knowledge:
          Map.new(ctx.scene.knowledge, fn {id, record} -> {id, %{record | scope: other_scope}} end)
    }

    assert {:ok, other_zone} = World.admit(other_world, other_scene)
    refute other_zone == ctx.zone
    assert {:error, :unauthorized} = World.attach(other_world, grant(ctx, "mara"), other_zone)
  end

  test "supervised zone receives explicit clocks and rolls only a fresh validated confirmation",
       ctx do
    {:ok, bundle} = Systems.load("fantasy_demo")
    parent = self()
    pin = ~U[2026-09-04 14:00:00.654321Z]

    clock = %{
      utc: fn ->
        Process.put({TempoClock, :clock}, TestClock)
        TestClock.put(pin)
        TempoClock.utc_now()
      end,
      monotonic: fn -> 500 end
    }

    draw = fn check ->
      send(parent, {:rolled, check["sides"]})
      [10]
    end

    {:ok, other_world} =
      Engine.start_world(__MODULE__.Registry, __MODULE__.Worlds,
        world_id: "clock-world",
        generation: 1
      )

    seed = scene(Systems.scene_rules(bundle))
    scope = %{seed.scope | world_id: "clock-world", generation: 1}

    seed = %{
      seed
      | scope: scope,
        time: %{seed.time | world_id: "clock-world"},
        knowledge: Map.new(seed.knowledge, fn {id, record} -> {id, %{record | scope: scope}} end)
    }

    seed = put_in(seed.actors["mara"].skills, %{"might" => 2})
    {:ok, zone} = World.admit(other_world, seed, clock: clock, draw: draw, receipt_limit: 1)
    other_ctx = %{ctx | world: other_world, zone: zone, scene: seed}
    {:ok, session} = World.attach(other_world, grant(other_ctx, "mara"), zone)

    assert {:error, :unavailable} =
             Session.propose(session, "invalid", %{type: "attempt", target_id: "secret"})

    refute_receive {:rolled, _}
    assert {:ok, _} = Session.propose(session, "check", %{type: "attempt", target_id: "moll"})
    assert {:ok, result} = Session.confirm(session, "roll-once", "check")
    assert_receive {:rolled, 20}
    assert {:ok, ^result} = Session.confirm(session, "roll-once", "check")
    refute_receive {:rolled, _}
    assert result.view.elapsed == 30
    assert result.effects |> hd() |> Map.fetch!(:result) == %{"outcome" => "success", "cost" => 1}
    [event] = :sys.get_state(zone).scene.events
    assert event.recorded_at == pin
    assert event.draws == [10]
    assert event.resolution.total == 12
    assert event.read_set.revision == 0
    assert :ok = World.pause(other_world, scope)
    assert {:ok, paused_result} = Session.confirm(session, "roll-once", "check")
    assert paused_result.effects == result.effects
    assert paused_result.view.status == :paused
    assert :ok = World.resume(other_world, scope)
    assert {:error, :capacity_limit} = Session.submit(session, request("over-limit", 3))
  end

  defp principal(ctx, actor, role),
    do: %{
      id: "principal-#{actor}-#{role}",
      campaign_id: "dock-campaign",
      actor_id: actor,
      role: role,
      scope: ctx.scene.scope,
      zone_id: ctx.scene.zone_id
    }

  defp grant(ctx, actor, role \\ :player) do
    {:ok, token} = World.grant(ctx.world, principal(ctx, actor, role))
    token
  end

  defp request(id, revision),
    do: %{id: id, revision: revision, intent: %{type: "take", target_id: "ration"}}
end
