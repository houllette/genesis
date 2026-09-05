defmodule Genesis.Persistence.Phase07RaceTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Genesis.CommittedWorldFixtures
  alias Genesis.{Campaigns, Experiences, Phase07Fixtures, Repo, WorldFixtures, WorldStandings}
  alias Genesis.Core.Scene

  alias Genesis.Persistence.{
    Actions,
    Authority,
    Codec,
    Event,
    Footprints,
    GlobalDependency,
    Reservation,
    Snapshot,
    Snapshots,
    Transfers
  }

  setup do
    ctx = unboxed(fn -> Phase07Fixtures.prepared_world() end)
    on_exit(fn -> cleanup(ctx) end)
    {:ok, Map.put(ctx, :tasks, start_supervised!(Task.Supervisor))}
  end

  for type <- ["take", "drop", "buy"] do
    @tag action: type
    test "independent #{type} and delivery contenders cannot spend or move twice", ctx do
      {ctx, principal, before, next, effects, intent, preview} =
        unboxed(fn ->
          ctx = WorldFixtures.experience_fixture(ctx)

          if ctx.action == "drop",
            do: commit_action(ctx, %{type: "take", target_id: "ration"}, "pickup")

          {:ok, principal, row} =
            Authority.principal(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

          {:ok, before} = Snapshots.load(row)

          intent =
            if ctx.action == "buy",
              do: %{type: "buy", target_id: "moll", quantity: 1},
              else: %{type: ctx.action, target_id: "ration"}

          {:ok, next, effects} =
            Scene.reduce(
              before,
              "mara",
              intent,
              Genesis.SceneFixtures.inputs(before, "local-action")
            )

          {:ok, preview} =
            Transfers.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks", %{
              "type" => "offer",
              "target_id" => "docks-representative",
              "quantity" => 1
            })

          {ctx, principal, before, next, effects, intent, preview}
        end)

      results =
        race(ctx, [
          fn ->
            Actions.commit(principal, before, next, %{
              id: "local-action",
              payload: {:direct, before.revision, intent},
              effects: effects
            })
          end,
          fn ->
            Transfers.begin(
              ctx.owner,
              ctx.world.id,
              ctx.experience.id,
              "mara",
              preview.token,
              "delivery"
            )
          end
        ])

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.any?(results, &(&1 in [{:error, :transfer_busy}, {:error, :stale_transfer}]))

      unboxed(fn ->
        assert {:ok, :recovered} = Transfers.recover(ctx.world.id)
        current = Phase07Fixtures.working(ctx, "bridge")
        assert current == before or current == next

        refute Repo.exists?(
                 from e in Event,
                   where:
                     e.experience_id == ^ctx.experience.id and like(e.core_event_id, "%/exchange")
               )
      end)
    end
  end

  test "opposite-direction actors reserve one operation and retain unique identities", ctx do
    {ctx, outward, inward} =
      unboxed(fn ->
        {:ok, _} =
          Campaigns.bind_character(
            ctx.owner,
            ctx.world.id,
            ctx.campaign.id,
            ctx.owner.user.id,
            "courier",
            "courier"
          )

        ctx = WorldFixtures.experience_fixture(ctx, participants: ["mara", "courier"])

        {:ok, preview} =
          Transfers.preview(ctx.owner, ctx.world.id, ctx.experience.id, "courier", "docks")

        {:ok, {:prepared, op}} =
          Transfers.begin(
            ctx.owner,
            ctx.world.id,
            ctx.experience.id,
            "courier",
            preview.token,
            "position"
          )

        commit_transfer(ctx, op)

        {:ok, outward} =
          Transfers.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks")

        {:ok, inward} =
          Transfers.preview(ctx.owner, ctx.world.id, ctx.experience.id, "courier", "bridge")

        {ctx, outward, inward}
      end)

    results =
      race(ctx, [
        fn ->
          Transfers.begin(
            ctx.owner,
            ctx.world.id,
            ctx.experience.id,
            "mara",
            outward.token,
            "out"
          )
        end,
        fn ->
          Transfers.begin(
            ctx.owner,
            ctx.world.id,
            ctx.experience.id,
            "courier",
            inward.token,
            "in"
          )
        end
      ])

    assert Enum.count(results, &match?({:ok, {:prepared, _}}, &1)) == 1
    assert {:error, :transfer_busy} in results
    {:ok, {:prepared, winner}} = Enum.find(results, &match?({:ok, _}, &1))

    unboxed(fn ->
      commit_transfer(ctx, winner)
      {:ok, rows} = Footprints.snapshots(ctx.experience)
      {:ok, states} = Footprints.load(rows)
      actors = Enum.flat_map(states, fn {_, s} -> Map.keys(s.actors) end)
      assert Enum.count(actors, &(&1 == "mara")) == 1
      assert Enum.count(actors, &(&1 == "courier")) == 1
    end)
  end

  test "competing campaigns cannot admit a second copy of a recruitable NPC", ctx do
    {first, second} =
      unboxed(fn ->
        {:ok, other} =
          Campaigns.create_campaign(ctx.owner, ctx.world.id, %{"name" => "Other crew"}, "other")

        for campaign <- [ctx.campaign, other] do
          {:ok, exp} =
            Experiences.create(
              ctx.owner,
              ctx.world.id,
              campaign.id,
              %{"name" => "Recruit Orin", "zone_id" => "bridge", "participants" => []},
              "exp-#{campaign.id}"
            )

          exp
        end
        |> List.to_tuple()
      end)

    results =
      race(
        ctx,
        for(
          exp <- [first, second],
          do: fn -> Experiences.start(ctx.owner, ctx.world.id, exp.id, 0) end
        )
      )

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, :claimed} in results

    unboxed(fn ->
      rows =
        Repo.all(
          from s in Snapshot, where: s.world_id == ^ctx.world.id and s.scope_kind == "experience"
        )

      assert length(rows) == 1
      {:ok, state} = Snapshots.load(hd(rows))
      assert state.actors["orin"].companion_policy["willing"]
      assert state.items["orin-satchel"].owner == {:actor, "orin"}
    end)
  end

  test "independent reports of the same accepted contribution produce one sourced update", ctx do
    {ctx, source} =
      unboxed(fn ->
        ctx = WorldFixtures.experience_fixture(ctx)

        {:ok, receipt} =
          commit_action(ctx, %{type: "offer", target_id: "reed", quantity: 1}, "offering")

        {ctx, hd(receipt.event_ids)}
      end)

    results =
      race(
        ctx,
        for(
          request <- ["report-a", "report-b"],
          do: fn ->
            WorldStandings.persist(ctx.owner, ctx.world.id, ctx.experience.id, source, request)
          end
        )
      )

    assert Enum.all?(results, &match?({:ok, %{"standing" => 1}}, &1))

    unboxed(fn ->
      assert Repo.aggregate(
               from(d in GlobalDependency, where: d.world_id == ^ctx.world.id),
               :count
             ) == 1

      reports =
        Repo.all(from e in Event, where: e.experience_id == ^ctx.experience.id)
        |> Enum.filter(fn e ->
          {:ok, data} = Codec.load(e.event)
          data.type == "standing_reported"
        end)

      assert length(reports) == 1
    end)
  end

  for committed <- [false, true] do
    @tag committed: committed
    test "damaged #{if committed, do: "committed", else: "prepared"} transfer retains both recovery fences",
         ctx do
      unboxed(fn ->
        ctx = WorldFixtures.experience_fixture(ctx)

        {:ok, preview} =
          Transfers.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks")

        {:ok, {:prepared, op}} =
          Transfers.begin(
            ctx.owner,
            ctx.world.id,
            ctx.experience.id,
            "mara",
            preview.token,
            "proof"
          )

        if ctx.committed do
          {:ok, source} = Snapshots.load(Repo.get!(Snapshot, op.source_snapshot_id))
          {:ok, dest} = Snapshots.load(Repo.get!(Snapshot, op.destination_snapshot_id))
          assert {:ok, _} = Transfers.commit(ctx.owner, op, source, dest, [])
        end

        row = Repo.get!(Snapshot, op.destination_snapshot_id)
        Repo.update!(Ecto.Changeset.change(row, digest: "damaged"))
        assert {:error, :corrupt_transfer} = Transfers.recover(ctx.world.id)
        if ctx.committed, do: assert({:error, :corrupt_transfer} = Transfers.finish(op))
        assert Repo.aggregate(from(r in Reservation, where: r.transfer_id == ^op.id), :count) == 2

        Repo.get!(Snapshot, row.id) |> Ecto.Changeset.change(digest: row.digest) |> Repo.update!()
        assert {:ok, :recovered} = Transfers.recover(ctx.world.id)
        assert Repo.aggregate(from(r in Reservation, where: r.transfer_id == ^op.id), :count) == 0
        place = if ctx.committed, do: "docks", else: "bridge"
        assert Phase07Fixtures.working(ctx, place).actors["mara"].id == "mara"
      end)
    end
  end

  defp commit_action(ctx, intent, id) do
    {:ok, principal, row} =
      Authority.principal(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

    {:ok, before} = Snapshots.load(row)

    {:ok, next, effects} =
      Scene.reduce(before, "mara", intent, Genesis.SceneFixtures.inputs(before, id))

    Actions.commit(principal, before, next, %{
      id: id,
      payload: {:direct, before.revision, intent},
      effects: effects
    })
  end

  defp commit_transfer(ctx, op) do
    {:ok, source} = Snapshots.load(Repo.get!(Snapshot, op.source_snapshot_id))
    {:ok, dest} = Snapshots.load(Repo.get!(Snapshot, op.destination_snapshot_id))
    {:ok, _} = Transfers.commit(ctx.owner, op, source, dest, [])
    {:ok, _} = Transfers.finish(op)
  end

  defp race(ctx, calls) do
    parent = self()

    tasks =
      for call <- calls do
        Task.Supervisor.async_nolink(ctx.tasks, fn -> run_contender(parent, call) end)
      end

    backends =
      for _ <- tasks do
        assert_receive {:connection, _pid, backend}
        backend
      end

    assert length(Enum.uniq(backends)) == 2
    Enum.each(tasks, &send(&1.pid, :go))
    Enum.map(tasks, &Task.await/1)
  end

  defp run_contender(parent, call), do: unboxed(fn -> contender(parent, call) end)

  defp contender(parent, call) do
    %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
    send(parent, {:connection, self(), backend})

    receive do
      :go -> call.()
    end
  end
end
