defmodule Genesis.Persistence.NetworkRaceTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Genesis.CommittedWorldFixtures
  alias Genesis.Persistence.{Curation, Event, Network, Receipt}
  alias Genesis.{Repo, WorldNetwork}

  setup do
    ctx = unboxed(fn -> Genesis.WorldFixtures.world_fixture() end)
    on_exit(fn -> cleanup(ctx) end)

    {:ok, %{"zone_id" => docks}} =
      unboxed(fn ->
        Curation.create_zone(ctx.owner, ctx.world.id, %{"name" => "Docks"}, "docks")
      end)

    {:ok, Map.merge(ctx, %{docks: docks, tasks: start_supervised!(Task.Supervisor)})}
  end

  test "two independent connections cannot both publish against network revision zero", ctx do
    parent = self()
    expected = %{generation: ctx.world.generation, revision: 0}

    contenders =
      for capacity <- [4, 6] do
        Task.Supervisor.async_nolink(ctx.tasks, fn ->
          unboxed(fn ->
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:ready, self(), backend})

            receive do
              :go ->
                WorldNetwork.persist(
                  ctx.owner,
                  ctx.world.id,
                  expected,
                  %{
                    "type" => "connection",
                    "from" => "bridge",
                    "to" => ctx.docks,
                    "condition" => "open",
                    "capacity" => capacity,
                    "visibility" => "public"
                  },
                  "author-#{capacity}"
                )
            end
          end)
        end)
      end

    backends =
      for _ <- contenders do
        assert_receive {:ready, _pid, backend}
        backend
      end

    assert length(Enum.uniq(backends)) == 2
    Enum.each(contenders, &send(&1.pid, :go))
    results = Enum.map(contenders, &Task.await/1)
    assert Enum.count(results, &match?({:ok, %{"revision" => 1}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :stale_revision})) == 1

    unboxed(fn ->
      row = Repo.get_by!(Network, world_id: ctx.world.id)
      assert row.revision == 1
      assert [%{"capacity" => capacity}] = row.data["connections"]
      assert capacity in [4, 6]

      assert Repo.aggregate(
               from(e in Event,
                 where: e.world_id == ^ctx.world.id and e.scope_key == "network:0"
               ),
               :count
             ) == 1

      assert Repo.aggregate(
               from(r in Receipt,
                 where: r.world_id == ^ctx.world.id and r.scope_key == "network:0"
               ),
               :count
             ) == 1
    end)
  end
end
