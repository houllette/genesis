defmodule Genesis.Persistence.CommittedRaceTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Genesis.CommittedWorldFixtures
  alias Genesis.{Campaigns, Experiences}
  alias Genesis.Persistence.{Claim, Codec, History, Tx}
  alias Genesis.Repo

  setup do
    ctx = unboxed(fn -> Genesis.WorldFixtures.world_fixture() end)
    on_exit(fn -> cleanup(ctx) end)
    {:ok, Map.put(ctx, :tasks, start_supervised!(Task.Supervisor))}
  end

  test "independent committed connections cannot claim the same published footprint twice", ctx do
    {one, two} =
      unboxed(fn ->
        {:ok, other} =
          Campaigns.create_campaign(ctx.owner, ctx.world.id, %{"name" => "Courier"}, "other")

        {:ok, one} =
          Experiences.create(
            ctx.owner,
            ctx.world.id,
            ctx.campaign.id,
            %{"name" => "One", "zone_id" => "bridge"},
            "one"
          )

        {:ok, two} =
          Experiences.create(
            ctx.owner,
            ctx.world.id,
            other.id,
            %{"name" => "Two", "zone_id" => "bridge"},
            "two"
          )

        {one, two}
      end)

    parent = self()

    contenders =
      for exp <- [one, two] do
        Task.Supervisor.async_nolink(ctx.tasks, fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> unboxed(fn -> Experiences.start(ctx.owner, ctx.world.id, exp.id, 0) end)
          end
        end)
      end

    for _ <- contenders, do: assert_receive({:ready, _pid})
    Enum.each(contenders, &send(&1.pid, :go))
    results = Enum.map(contenders, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :claimed})) == 1

    unboxed(fn ->
      assert Repo.aggregate(from(c in Claim, where: c.world_id == ^ctx.world.id), :count) == 7

      assert Repo.all(
               from c in Claim,
                 where: c.world_id == ^ctx.world.id,
                 select: c.experience_id,
                 distinct: true
             )
             |> length() == 1
    end)
  end

  test "an uncommitted early event cannot be skipped by a faster later writer's history cursor",
       ctx do
    parent = self()
    before_cursor = ctx.world.cursor

    early =
      Task.Supervisor.async_nolink(ctx.tasks, fn ->
        unboxed(fn ->
          Tx.run(ctx.world.id, fn world ->
            event = event(world, ctx.owner.user.id, "early")
            send(parent, {:uncommitted, self()})

            receive do
              :commit -> {:ok, event}
            end
          end)
        end)
      end)

    assert_receive {:uncommitted, early_pid}

    late =
      Task.Supervisor.async_nolink(ctx.tasks, fn ->
        send(parent, :late_started)
        unboxed(fn -> Tx.run(ctx.world.id, &{:ok, event(&1, ctx.owner.user.id, "late")}) end)
      end)

    assert_receive :late_started
    send(early_pid, :commit)
    assert {:ok, first} = Task.await(early)
    assert {:ok, second} = Task.await(late)
    assert second.cursor == first.cursor + 1

    unboxed(fn ->
      assert {:ok, %{events: [one], next_cursor: cursor}} =
               History.page(ctx.owner, ctx.world.id, after: before_cursor, limit: 1)

      assert one.type == "early"

      assert {:ok, %{events: [two]}} =
               History.page(ctx.owner, ctx.world.id, after: cursor, limit: 1)

      assert two.type == "late"
    end)
  end

  defp event(world, user, type),
    do:
      Tx.event!(world, %{
        kind: "world",
        scope_key: "race",
        principal_id: user,
        audience_users: [user],
        event: Codec.dump!(%{type: type, result: %{}})
      })
end
