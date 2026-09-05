defmodule Genesis.Persistence.DurableAuthorityTest do
  use Genesis.DataCase, async: false
  @moduletag capture_log: true
  alias Genesis.Campaigns
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}
  alias Genesis.Persistence.{Event, Receipt, Snapshot, Snapshots}
  import Genesis.WorldFixtures

  setup do
    ctx = world_fixture()

    assert {:ok, _} =
             Campaigns.bind_character(
               ctx.owner,
               ctx.world.id,
               ctx.campaign.id,
               ctx.owner.user.id,
               "mara"
             )

    {:ok, experience_fixture(ctx)}
  end

  test "detached sessions release grant capacity instead of exhausting a long-running world",
       ctx do
    tree(ctx)

    for _index <- 1..260 do
      assert {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
      assert :ok = Session.detach(session)
    end

    assert {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

    assert {:error, :invalid_request} =
             Session.submit_step(session, "forged", 0, %{
               revision: 0,
               intent: %{type: "take", target_id: "ration"},
               actor_id: "courier"
             })

    assert {:ok, %{revision: 0}} = Session.view(session)
  end

  test "acknowledged actions survive Zone loss; lost confirmations recover without a new proposal or roll",
       ctx do
    tree(ctx)
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    assert {:ok, _} = Session.propose(session, "help-preview", %{type: "help", target_id: "moll"})
    assert {:ok, first} = Session.confirm(session, "help", "help-preview")
    assert first.durability == :durable
    assert first.view.elapsed == 60
    zone = :sys.get_state(session).zone
    monitor = Process.monitor(zone)
    Process.exit(zone, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^zone, :killed}
    {:ok, replacement} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    assert {:ok, retry} = Session.confirm(replacement, "help", "help-preview")
    assert retry.effects == first.effects
    assert retry.view.elapsed == 60
    assert Enum.any?(retry.view.knowledge, &(&1.predicate == "helped" and &1.value == true))

    assert Repo.aggregate(
             from(r in Receipt, where: r.world_id == ^ctx.world.id and r.request_id == "help"),
             :count
           ) == 1

    assert {:ok, base} = Snapshots.load(ctx.published)
    assert base.elapsed == 0
    assert base.actors["mara"].resources["effort"] == 10
  end

  for boundary <- [:before_commit, :after_commit, :after_install] do
    @tag boundary: boundary
    test "crash matrix at #{boundary} commits exactly once", ctx do
      boundary = ctx.boundary
      fault = fn stage -> if stage == boundary, do: exit({:injected, stage}), else: :ok end
      tree(ctx, fault: fault)
      {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
      assert catch_exit(Session.submit(session, request()))
      snapshot = Repo.get!(Snapshot, ctx.snapshot.id)
      assert {:ok, state} = Snapshots.load(snapshot)
      expected = if boundary == :before_commit, do: 0, else: 1
      assert state.revision == expected

      assert Repo.aggregate(
               from(e in Event, where: e.snapshot_id == ^snapshot.id and e.actor_id == "mara"),
               :count
             ) == expected

      world =
        GenServer.whereis(
          Genesis.Engine.Supervisor.via(Genesis.Engine.Registry, {:world, ctx.world.id})
        )

      :sys.replace_state(world, &%{&1 | zone_opts: []})
      {:ok, replacement} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
      assert {:ok, result} = Session.submit(replacement, request())
      assert result.view.revision == 1

      assert [%{owner: {:actor, "mara"}, quantity: 2}] =
               Enum.filter(result.view.items, &(&1.id == "ration"))
    end
  end

  test "compound receipts resume the first unresolved step without paying accepted costs again",
       ctx do
    tree(ctx)
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, _} = Session.propose(session, "help", %{type: "help", target_id: "moll"})
    assert {:ok, first} = Session.confirm_step(session, "distract-and-take", 0, "help")

    assert {:error, :unavailable} =
             Session.submit_step(session, "distract-and-take", 1, %{
               revision: 1,
               intent: %{type: "take", target_id: "missing"}
             })

    assert {:error, :earlier_step_missing} =
             Session.submit_step(session, "distract-and-take", 2, %{
               revision: 1,
               intent: %{type: "take", target_id: "ration"}
             })

    assert :ok = Session.detach(session)
    {:ok, replacement} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    assert {:ok, retry} = Session.confirm_step(replacement, "distract-and-take", 0, "help")
    assert retry.effects == first.effects
    assert retry.view.elapsed == 60

    assert {:ok, second} =
             Session.submit_step(replacement, "distract-and-take", 1, %{
               revision: 1,
               intent: %{type: "take", target_id: "ration"}
             })

    assert second.view.elapsed == 60
    assert second.view.revision == 2
  end

  defp tree(ctx, zone_opts \\ []) do
    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: ctx.world.generation,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres,
       zone_opts: zone_opts}
    )
  end

  defp request, do: %{id: "take", revision: 0, intent: %{type: "take", target_id: "ration"}}
end
