defmodule Genesis.Persistence.ExperienceTest do
  use Genesis.DataCase, async: true
  alias Genesis.{Campaigns, Experiences}
  alias Genesis.Persistence.{Claim, Snapshots, Window}
  import Genesis.WorldFixtures

  test "drafts claim nothing; start pins the base and claims canonical identities across campaigns" do
    ctx = world_fixture()

    {:ok, first} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "Bridge", "zone_id" => "bridge", "participants" => ["mara"]},
        "first"
      )

    refute Repo.exists?(from c in Claim, where: c.world_id == ^ctx.world.id)
    assert {:ok, active} = Experiences.start(ctx.owner, ctx.world.id, first.id, 0)
    assert {:ok, ^active} = Experiences.start(ctx.owner, ctx.world.id, first.id, 0)
    assert active.status == "active"
    assert Repo.aggregate(from(c in Claim, where: c.experience_id == ^active.id), :count) == 7

    {:ok, other} =
      Campaigns.create_campaign(ctx.owner, ctx.world.id, %{"name" => "Courier"}, "other")

    {:ok, second} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        other.id,
        %{"name" => "Collision", "zone_id" => "bridge"},
        "second"
      )

    assert {:error, :claimed} = Experiences.start(ctx.owner, ctx.world.id, second.id, 0)
    assert Repo.aggregate(from(w in Window, where: w.world_id == ^ctx.world.id), :count) == 1
    assert {:ok, base} = Snapshots.load(ctx.published)
    assert base == ctx.seed
    assert_enqueued(worker: Genesis.Persistence.DeliverEvent)
  end

  test "start offsets are unavailable and snapshot corruption or pin drift fails closed" do
    ctx = world_fixture()

    assert {:error, :invalid_experience} =
             Experiences.create(
               ctx.owner,
               ctx.world.id,
               ctx.campaign.id,
               %{"name" => "Future", "zone_id" => "bridge", "start_offset" => 1},
               "future"
             )

    assert {:error, :corrupt_snapshot} = Snapshots.load(%{ctx.published | digest: "broken"})
    invalid = %{ctx.seed | rules_ref: Map.put(ctx.seed.rules_ref, "version", 99)}
    assert {:error, :incompatible_snapshot} = Snapshots.compatible(ctx.world, invalid)
  end
end
