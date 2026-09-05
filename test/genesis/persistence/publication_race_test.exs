defmodule Genesis.Persistence.PublicationRaceTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Genesis.CommittedWorldFixtures
  alias Genesis.{Content, Repo}
  alias Genesis.Persistence.{Control, Entity, Event, Incorporation, Publication, Snapshots, Tx}

  setup do
    ctx =
      unboxed(fn ->
        ctx =
          Genesis.WorldFixtures.world_fixture(zero_duration: true)
          |> Genesis.WorldFixtures.experience_fixture()

        {:ok, before} = Snapshots.load(ctx.snapshot)

        {:ok, _} =
          Control.change(ctx.owner, ctx.snapshot.id, before, :ready, before.revision, "seal", [])

        {:ok, prepared} = Incorporation.prepare(ctx.owner, ctx.world.id, ctx.experience.id)
        Map.put(ctx, :prepared, prepared)
      end)

    on_exit(fn -> cleanup(ctx) end)
    {:ok, Map.put(ctx, :tasks, start_supervised!(Task.Supervisor))}
  end

  test "independent confirmations reserve one publication and never expose a receipt before installation",
       ctx do
    parent = self()

    tasks =
      for request <- ["one", "two"] do
        Task.Supervisor.async_nolink(ctx.tasks, fn ->
          unboxed(fn ->
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:ready, self(), backend})

            receive do
              :go -> Incorporation.begin(ctx.owner, ctx.world.id, ctx.prepared, request)
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
    assert Enum.count(results, &match?({:ok, %Publication{}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :publication_busy})) == 1
    {:ok, op} = Enum.find(results, &match?({:ok, _}, &1))

    unboxed(fn ->
      assert {:error, :publication_busy} = Content.view(ctx.owner, ctx.world.id, "bridge")
      assert {:ok, result} = Incorporation.publish(ctx.owner, op, [])

      assert {:error, :publication_busy} =
               Incorporation.receipt(ctx.owner, ctx.world.id, ctx.prepared.id, op.request_id)

      # No runtime caches exist in this committed-connection harness: cold recovery is safe.
      assert {:ok, :recovered} = Incorporation.recover(ctx.world.id)

      assert {:ok, ^result} =
               Incorporation.receipt(ctx.owner, ctx.world.id, ctx.prepared.id, op.request_id)

      assert Repo.get!(Publication, op.id).status == "installed"
      assert Repo.aggregate(from(e in Event, where: e.id in ^result["event_ids"]), :count) == 1
      assert {:ok, _} = Content.view(ctx.owner, ctx.world.id, "bridge")
    end)
  end

  test "cold recovery keeps the fence if committed ownership no longer matches the snapshots",
       ctx do
    unboxed(fn ->
      {:ok, op} = Incorporation.begin(ctx.owner, ctx.world.id, ctx.prepared, "publish")
      {:ok, _} = Incorporation.publish(ctx.owner, op, [])
      entity = Repo.get_by!(Entity, world_id: ctx.world.id, kind: "actor", entity_id: "mara")
      Tx.update!(entity, %{zone_id: "corrupt-owner"})
      assert {:error, :corrupt_publication} = Incorporation.recover(ctx.world.id)
      assert Repo.get!(Publication, op.id).status == "committed"
      assert {:error, :publication_busy} = Content.view(ctx.owner, ctx.world.id, "bridge")
    end)
  end
end
