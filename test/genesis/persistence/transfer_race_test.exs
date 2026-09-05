defmodule Genesis.Persistence.TransferRaceTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Genesis.CommittedWorldFixtures
  alias Genesis.{Campaigns, Repo, WorldNetwork}
  alias Genesis.Core.Scene

  alias Genesis.Persistence.{
    Actions,
    Authority,
    Curation,
    Event,
    Footprints,
    Reservation,
    Snapshots,
    Transfer,
    Transfers
  }

  setup do
    ctx =
      unboxed(fn ->
        ctx = Genesis.WorldFixtures.world_fixture(zero_duration: true)

        {:ok, %{"zone_id" => docks}} =
          Curation.create_zone(ctx.owner, ctx.world.id, %{"name" => "Docks"}, "docks")

        {:ok, _} =
          WorldNetwork.persist(
            ctx.owner,
            ctx.world.id,
            %{generation: 0, revision: 0},
            %{
              "type" => "connection",
              "from" => "bridge",
              "to" => docks,
              "condition" => "open",
              "capacity" => 1,
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

        Map.put(Genesis.WorldFixtures.experience_fixture(ctx), :docks, docks)
      end)

    on_exit(fn -> cleanup(ctx) end)
    {:ok, Map.put(ctx, :tasks, start_supervised!(Task.Supervisor))}
  end

  test "independent contenders reserve one transfer; a precomputed take cannot cross the fence",
       ctx do
    {preview, principal, before, next, effects} =
      unboxed(fn ->
        {:ok, preview} =
          Transfers.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", ctx.docks)

        {:ok, principal, row} =
          Authority.principal(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

        {:ok, before} = Snapshots.load(row)

        {:ok, next, effects} =
          Scene.reduce(
            before,
            "mara",
            %{type: "take", target_id: "ration"},
            Genesis.SceneFixtures.inputs(before, "take")
          )

        {preview, principal, before, next, effects}
      end)

    parent = self()

    tasks =
      for request <- ["one", "two"] do
        Task.Supervisor.async_nolink(ctx.tasks, fn ->
          unboxed(fn ->
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:ready, self(), backend})

            receive do
              :go ->
                Transfers.begin(
                  ctx.owner,
                  ctx.world.id,
                  ctx.experience.id,
                  "mara",
                  preview.token,
                  request
                )
            end
          end)
        end)
      end

    backends =
      for _ <- tasks do
        assert_receive {:ready, _pid, backend}
        backend
      end

    assert length(Enum.uniq(backends)) == 2
    Enum.each(tasks, &send(&1.pid, :go))
    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, {:prepared, _}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :transfer_busy})) == 1

    unboxed(fn ->
      assert Repo.aggregate(
               from(r in Reservation,
                 join: t in Transfer,
                 on: r.transfer_id == t.id,
                 where: t.world_id == ^ctx.world.id
               ),
               :count
             ) == 2

      assert {:error, :transfer_busy} =
               Actions.commit(principal, before, next, %{
                 id: "take",
                 payload: {:direct, before.revision, %{type: "take", target_id: "ration"}},
                 effects: effects
               })

      assert Repo.aggregate(
               from(e in Event,
                 where: e.experience_id == ^ctx.experience.id and not is_nil(e.actor_id)
               ),
               :count
             ) == 0

      assert {:ok, :recovered} = Transfers.recover(ctx.world.id)
      {:ok, row} = Footprints.actor_snapshot(ctx.experience, "mara")
      {:ok, still_here} = Snapshots.load(row)
      assert still_here == before
      assert {:ok, rows} = Footprints.snapshots(ctx.experience)
      assert length(rows) == 2
    end)
  end
end
