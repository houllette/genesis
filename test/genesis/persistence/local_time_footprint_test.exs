defmodule Genesis.Persistence.LocalTimeFootprintTest do
  use Genesis.DataCase, async: false
  @moduletag capture_log: true
  import Genesis.Phase07Fixtures
  alias Genesis.Campaigns
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}
  alias Genesis.Experiences
  alias Genesis.Persistence.{Experience, LocalTime, Seals}
  alias Genesis.Travel

  setup tags do
    ctx = active_world(zero_duration: !tags[:positive])

    start_supervised!(
      {WorldSupervisor,
       registry: Genesis.Engine.Registry,
       world_id: ctx.world.id,
       generation: 0,
       owner: self(),
       storage: :postgres}
    )

    unless tags[:stationary] do
      {:ok, preview} = Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "docks")

      {:ok, _} =
        Travel.move(ctx.owner, ctx.world.id, ctx.experience.id, "mara", preview.token, "travel")
    end

    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    Map.put(ctx, :session, session)
  end

  @tag stationary: true
  test "an independent courier can finish while the group stays paused, without publication or claim release",
       ctx do
    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, :pause, 0, "pause"}
             )

    {:ok, campaign} =
      Campaigns.create_campaign(ctx.owner, ctx.world.id, %{"name" => "Courier"}, "courier")

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        campaign.id,
        ctx.owner.user.id,
        "docks-courier",
        "courier-bind"
      )

    {:ok, exp} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        campaign.id,
        %{"name" => "Two-hour errand", "zone_id" => "docks", "participants" => ["docks-courier"]},
        "errand"
      )

    {:ok, exp} = Experiences.start(ctx.owner, ctx.world.id, exp.id, 0)
    {:ok, basis} = Seals.basis(exp)

    declaration = %{
      "elapsed_seconds" => 7200,
      "outcome" => "completed",
      "reason" => "Delivered the dispatch",
      "basis" => basis
    }

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, exp.id, {:finish, declaration}, 0, "courier-finish"}
             )

    assert Repo.get!(Experience, exp.id).status == "ready"
    assert Repo.get!(Experience, ctx.experience.id).status == "paused"
    assert Repo.get!(Genesis.Persistence.World, ctx.world.id).fictional_time == 0

    assert {:error, :incorporation_not_ready} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, exp.id})

    assert Repo.exists?(from c in Genesis.Persistence.Claim, where: c.experience_id == ^exp.id)

    assert Repo.exists?(
             from c in Genesis.Persistence.Claim, where: c.experience_id == ^ctx.experience.id
           )
  end

  test "completion binds destination outcomes as well as the unchanged origin revision", ctx do
    {:ok, basis} = Seals.basis(Repo.get!(Experience, ctx.experience.id))

    declaration = %{
      "elapsed_seconds" => 0,
      "outcome" => "completed",
      "reason" => "Reviewed the delivery",
      "basis" => basis
    }

    origin = working(ctx, "bridge")
    {:ok, _} = Session.propose(ctx.session, "help", %{type: "help", target_id: "docks-merchant"})
    {:ok, _} = Session.confirm(ctx.session, "help", "help")
    assert working(ctx, "bridge").revision == origin.revision

    assert {:error, :stale_completion} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, {:finish, declaration}, origin.revision, "finish"}
             )

    assert Repo.get!(Experience, ctx.experience.id).status == "active"
    {:ok, basis} = Seals.basis(Repo.get!(Experience, ctx.experience.id))

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, {:finish, %{declaration | "basis" => basis}},
                origin.revision, "finish"}
             )

    assert Seals.validate(Repo.get!(Experience, ctx.experience.id)) == :ok
  end

  @tag positive: true
  test "timed actions use one cursor and explicit catch-up enables travel without double charging",
       ctx do
    before = working(ctx, "docks")
    {:ok, _} = Session.propose(ctx.session, "help", %{type: "help", target_id: "docks-merchant"})
    assert {:ok, _} = Session.confirm(ctx.session, "help", "help")
    assert working(ctx, "docks").elapsed == before.elapsed + 60

    assert {:error, :time_reconciliation_unavailable} =
             Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "bridge")

    duration = %{"unit" => "second", "value" => 0, "reason" => "Catch the bridge up to the party"}

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, {:elapse, duration}, working(ctx, "bridge").revision,
                "time"}
             )

    assert working(ctx, "bridge").elapsed == 60
    assert working(ctx, "docks").elapsed == 60

    assert {:ok, preview} =
             Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", "bridge")

    assert {:ok, _} =
             Travel.move(
               ctx.owner,
               ctx.world.id,
               ctx.experience.id,
               "mara",
               preview.token,
               "return"
             )

    assert {:ok, summary} =
             LocalTime.summary(Repo.get!(Experience, ctx.experience.id))

    assert summary.elapsed_seconds == 60
    assert working(ctx, "bridge").actors["mara"].resources["effort"] == 9
  end
end
