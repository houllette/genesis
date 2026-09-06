defmodule Genesis.Persistence.TimedRaceTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Genesis.CommittedWorldFixtures
  alias Genesis.Persistence.{Control, Preparation, Preparations, Seals, Snapshots, Tx}
  alias Genesis.Repo

  test "independent database connections cannot seal two candidates for one window" do
    ctx =
      unboxed(fn ->
        ctx = Genesis.WorldFixtures.world_fixture() |> Genesis.WorldFixtures.experience_fixture()
        {:ok, basis} = Seals.basis(ctx.experience)
        {:ok, state} = Snapshots.load(ctx.snapshot)

        {:ok, _} =
          Control.change(
            ctx.owner,
            ctx.snapshot.id,
            state,
            {:finish,
             %{
               "elapsed_seconds" => 7200,
               "outcome" => "completed",
               "reason" => "Finished",
               "basis" => basis
             }},
            0,
            "finish",
            []
          )

        ctx
      end)

    on_exit(fn -> cleanup(ctx) end)
    tasks = start_supervised!(Task.Supervisor)
    parent = self()

    input = %{
      "decisions" => %{ctx.experience.id => %{"mode" => "include", "reason" => "Reviewed"}},
      "downtime_seconds" => 0,
      "reason" => "Window review"
    }

    work =
      for request <- ["one", "two"] do
        Task.Supervisor.async_nolink(tasks, fn ->
          unboxed(fn ->
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:ready, self(), backend})

            receive do
              :go -> Preparations.start(ctx.owner, ctx.world.id, input, request)
            end
          end)
        end)
      end

    backends =
      for _ <- work do
        assert_receive {:ready, _, backend}, 2000
        backend
      end

    assert length(Enum.uniq(backends)) == 2
    Enum.each(work, &send(&1.pid, :go))
    results = Enum.map(work, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :window_sealed})) == 1

    unboxed(fn ->
      assert Repo.aggregate(from(p in Preparation, where: p.world_id == ^ctx.world.id), :count) ==
               1

      assert {:ok, world} = Tx.run(ctx.world.id, &{:ok, &1})
      assert world.fictional_time == 0
    end)
  end
end
