defmodule Genesis.Persistence.PreparationsTest do
  use Genesis.DataCase, async: false
  import Genesis.WorldFixtures
  alias Genesis.Content
  alias Genesis.Engine.{Runtime, WorldSupervisor}
  alias Genesis.Experiences
  alias Genesis.Persistence.{Experience, Preparation, PrepareTimeline, Seals, World}

  test "parallel completion prepares the maximum end, resumes a saved batch, and does not publish early" do
    ctx = world_fixture()

    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: 0,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres}
    )

    {:ok, %{"zone_id" => docks}} =
      Content.create_zone(ctx.owner, ctx.world.id, %{"name" => "Docks"}, "docks")

    ctx = experience_fixture(ctx)

    {:ok, courier} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "Courier", "zone_id" => docks},
        "courier"
      )

    {:ok, courier} = Experiences.start(ctx.owner, ctx.world.id, courier.id, 0)
    finish(ctx, ctx.experience, 259_200)
    finish(ctx, courier, 7200)

    attrs = %{
      "decisions" =>
        Map.new(
          [ctx.experience, courier],
          &{&1.id, %{"mode" => "include", "reason" => "Reviewed actual outcomes"}}
        ),
      "downtime_seconds" => 0,
      "reason" => "Bring both stories into history"
    }

    assert {:ok, %{"preparation_id" => id} = result} =
             Runtime.call(ctx.owner, ctx.world.id, {:prepare_time, attrs, "prepare"})

    assert {:ok, ^result} =
             Runtime.call(ctx.owner, ctx.world.id, {:prepare_time, attrs, "prepare"})

    assert_enqueued(worker: PrepareTimeline, args: %{preparation_id: id})
    preparation = Repo.get!(Preparation, id)
    assert preparation.manifest["target"] == 259_200
    assert Repo.get!(World, ctx.world.id).fictional_time == 0

    assert :ok =
             perform_job(PrepareTimeline, %{
               "preparation_id" => id,
               "world_id" => ctx.world.id,
               "generation" => 0
             })

    prepared = Repo.get!(Preparation, id)
    assert prepared.status == "ready"

    assert :ok =
             perform_job(PrepareTimeline, %{
               "preparation_id" => id,
               "world_id" => ctx.world.id,
               "generation" => 0
             })

    assert Repo.get!(Preparation, id).digest == prepared.digest
    assert Repo.get!(Experience, courier.id).status == "ready"
    assert Repo.get!(World, ctx.world.id).fictional_time == 0
    assert {:ok, preview} = Runtime.call(ctx.owner, ctx.world.id, {:preview_time, id})

    assert {:ok, published} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert published["world_time"] == 259_200

    assert {:ok, ^published} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert Repo.get!(Experience, courier.id).status == "incorporated"
    assert Repo.get!(World, ctx.world.id).fictional_time == 259_200
  end

  defp finish(ctx, exp, seconds) do
    {:ok, basis} = Seals.basis(Repo.get!(Experience, exp.id))

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, exp.id,
                {:finish,
                 %{
                   "elapsed_seconds" => seconds,
                   "outcome" => "completed",
                   "reason" => "The errand is finished",
                   "basis" => basis
                 }}, 0, "finish-" <> exp.id}
             )
  end
end
