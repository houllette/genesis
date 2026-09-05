defmodule Genesis.Persistence.LocalTimeTest do
  use Genesis.DataCase, async: false
  @moduletag capture_log: true
  alias Genesis.Persistence.{Checkpoint, LocalTime, Replay}
  alias Genesis.Workspace
  import Genesis.WorldFixtures
  alias Genesis.Campaigns
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}
  alias Genesis.Persistence.{Claim, Codec, Event, Experience, Seals, Snapshot, Snapshots, World}

  setup do
    ctx = world_fixture()

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara"
      )

    ctx = experience_fixture(ctx)

    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: ctx.world.generation,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres}
    )

    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    Map.put(ctx, :session, session)
  end

  test "scene time is explicit, durable and idempotent, then finish declares a total not another duration",
       ctx do
    {:ok, _} = Session.propose(ctx.session, "help", %{type: "help", target_id: "moll"})
    {:ok, _} = Session.confirm(ctx.session, "help", "help")
    assert working(ctx).elapsed == 60

    duration = %{"unit" => "minute", "value" => 4, "reason" => "Walk to the gate"}
    assert {:ok, entry} = control(ctx, {:elapse, duration}, 1, "walk")
    assert {:ok, ^entry} = control(ctx, {:elapse, duration}, 1, "walk")
    assert working(ctx).elapsed == 300
    assert Repo.get!(World, ctx.world.id).fictional_time == 0

    declaration =
      declaration(ctx, %{
        "elapsed_seconds" => 3600,
        "outcome" => "abandoned",
        "reason" => "The crew retreated"
      })

    assert {:ok, result} = control(ctx, {:finish, declaration}, 2, "finish")
    assert {:ok, ^result} = control(ctx, {:finish, declaration}, 2, "finish")
    exp = Repo.get!(Experience, ctx.experience.id)
    assert exp.status == "ready"
    assert exp.completion["format"] == 3
    assert exp.completion["elapsed_seconds"] == 3600
    assert exp.completion["recorded_elapsed_seconds"] == 300
    assert exp.completion["declaration"]["outcome"] == "abandoned"
    assert Seals.validate(exp) == :ok
    assert working(ctx).elapsed == 300

    assert working(ctx).actors["mara"].resources["effort"] ==
             ctx.seed.actors["mara"].resources["effort"] - 1

    assert Repo.exists?(from c in Claim, where: c.experience_id == ^exp.id)

    assert {:error, :time_reconciliation_unavailable} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, exp.id})

    assert {:error, :request_conflict} =
             control(ctx, {:finish, %{declaration | "elapsed_seconds" => 7200}}, 2, "finish")

    assert {:error, _} = control(ctx, {:elapse, duration}, 3, "after-finish")
  end

  test "completion cannot precede paid action time", ctx do
    {:ok, _} = Session.propose(ctx.session, "help", %{type: "help", target_id: "moll"})
    {:ok, _} = Session.confirm(ctx.session, "help", "help")

    declaration =
      declaration(ctx, %{
        "elapsed_seconds" => 59,
        "outcome" => "completed",
        "reason" => "Too short"
      })

    assert {:error, :duration_before_recorded_time} =
             control(ctx, {:finish, declaration}, 1, "short")

    assert Repo.get!(Experience, ctx.experience.id).status == "active"
    assert working(ctx).elapsed == 60
  end

  test "zero scene duration stays a sourced point and invalid duration shapes commit nothing",
       ctx do
    for amount <- [
          %{"unit" => "second", "value" => -1, "reason" => "Invalid"},
          %{"unit" => "second", "value" => 1, "reason" => ""},
          %{"unit" => "second", "value" => 1, "reason" => "Extra", "permission" => "gm"},
          %{"unit" => "month", "value" => 1, "reason" => "Ordinal has no months"}
        ] do
      assert {:error, _} = control(ctx, {:elapse, amount}, 0, "invalid")
      assert working(ctx).revision == 0
    end

    amount = %{"unit" => "second", "value" => 0, "reason" => "An instantaneous scene change"}
    assert {:ok, _} = control(ctx, {:elapse, amount}, 0, "point")
    assert working(ctx).revision == 1
    assert working(ctx).elapsed == 0
    assert {:ok, review} = Workspace.experience_review(ctx.owner, ctx.world.id, ctx.experience.id)
    assert [%{seconds: 0, from: 0, to: 0}] = review.time_entries
  end

  test "paused scene edits reject; completion can retain a needs-review outcome and its costs",
       ctx do
    assert {:ok, _} = control(ctx, :pause, 0, "pause")
    duration = %{"unit" => "hour", "value" => 1, "reason" => "Not while paused"}
    assert {:error, :invalid_status_transition} = control(ctx, {:elapse, duration}, 1, "elapse")

    attrs =
      declaration(ctx, %{
        "elapsed_seconds" => 0,
        "outcome" => "failed",
        "reason" => "The table needs to reconcile a disputed choice",
        "review_required" => true
      })

    assert {:ok, _} = control(ctx, {:finish, attrs}, 1, "finish")
    exp = Repo.get!(Experience, ctx.experience.id)
    assert exp.status == "needs_review"
    assert Seals.validate(exp) == :ok
    assert {:error, :sealed_footprint_changed} = Seals.validate(%{exp | status: "ready"})
    assert {:error, :invalid_status_transition} = control(ctx, :resume, 2, "resume")
    assert {:error, _} = Session.propose(ctx.session, "late", %{type: "help", target_id: "moll"})
  end

  test "changing a sealed total or outcome cannot validate against the immutable completion source",
       ctx do
    attrs =
      declaration(ctx, %{"elapsed_seconds" => 0, "outcome" => "completed", "reason" => "Done"})

    assert {:ok, _} = control(ctx, {:finish, attrs}, 0, "finish")
    exp = Repo.get!(Experience, ctx.experience.id)
    tampered = put_in(exp.completion["declaration"]["outcome"], "abandoned")
    assert {:error, :sealed_footprint_changed} = Seals.validate(tampered)
    assert :ok = Seals.validate(exp)
  end

  test "a campaign spectator cannot finish, advance time, or read the GM ledger", ctx do
    viewer = Genesis.Accounts.Scope.for_user(Genesis.AccountsFixtures.user_fixture())

    {:ok, _} =
      Campaigns.add_member(ctx.owner, ctx.world.id, ctx.campaign.id, viewer.user.id, "spectator")

    attrs =
      declaration(ctx, %{"elapsed_seconds" => 0, "outcome" => "completed", "reason" => "Forged"})

    assert {:error, :unauthorized} =
             Runtime.call(
               viewer,
               ctx.world.id,
               {:status, ctx.experience.id, {:finish, attrs}, 0, "forged"}
             )

    assert {:error, :unauthorized} =
             Workspace.experience_review(viewer, ctx.world.id, ctx.experience.id)

    assert working(ctx).revision == 0
    assert Repo.get!(Experience, ctx.experience.id).status == "active"
  end

  test "new GM access does not disclose private historical time explanations", ctx do
    duration = %{
      "unit" => "minute",
      "value" => 1,
      "reason" => "Private negotiation with the envoy"
    }

    assert {:ok, _} = control(ctx, {:elapse, duration}, 0, "private-time")
    later = Genesis.Accounts.Scope.for_user(Genesis.AccountsFixtures.user_fixture())
    {:ok, _} = Campaigns.add_member(ctx.owner, ctx.world.id, ctx.campaign.id, later.user.id, "gm")
    assert {:ok, review} = Workspace.experience_review(later, ctx.world.id, ctx.experience.id)
    assert review.elapsed_seconds == 60
    assert review.time_entries == []
    assert {:ok, review} = Workspace.experience_review(ctx.owner, ctx.world.id, ctx.experience.id)
    assert [%{reason: "Private negotiation with the envoy"}] = review.time_entries
  end

  test "zero-time finish can still publish once and remains inspectable afterward", ctx do
    attrs =
      declaration(ctx, %{
        "elapsed_seconds" => 0,
        "outcome" => "completed",
        "reason" => "No elapsed time"
      })

    assert {:ok, _} = control(ctx, {:finish, attrs}, 0, "finish")

    {:ok, preview} =
      Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    assert {:ok, result} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert {:ok, ^result} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert {:ok, review} =
             Workspace.experience_review(ctx.owner, ctx.world.id, ctx.experience.id)

    assert review.experience.status == "incorporated"
    assert review.elapsed_seconds == 0
  end

  for action <- [:elapse, :finish],
      boundary <- [:control_before_commit, :control_after_commit, :control_after_install] do
    @tag action: action, boundary: boundary
    test "#{action} interrupted at #{boundary} recovers one result", ctx do
      payload =
        if ctx.action == :elapse,
          do: %{"unit" => "minute", "value" => 2, "reason" => "A scene passes"},
          else:
            declaration(ctx, %{
              "elapsed_seconds" => 0,
              "outcome" => "abandoned",
              "reason" => "Retreated"
            })

      zone =
        GenServer.whereis(
          Genesis.Engine.Supervisor.via(
            Genesis.Engine.Registry,
            {:zone, {Genesis.Core.Scope.key(working(ctx).scope), "bridge"}}
          )
        )

      fault = fn stage -> if stage == ctx.boundary, do: exit({:injected, stage}), else: :ok end
      :sys.replace_state(zone, &%{&1 | storage_opts: [fault: fault]})

      assert {:error, :command_interrupted} =
               control(ctx, {ctx.action, payload}, 0, "interrupted")

      assert working(ctx).revision == if(ctx.boundary == :control_before_commit, do: 0, else: 1)
      assert {:ok, result} = control(ctx, {ctx.action, payload}, 0, "interrupted")
      assert {:ok, ^result} = control(ctx, {ctx.action, payload}, 0, "interrupted")
      assert working(ctx).revision == 1
      assert working(ctx).elapsed == if(ctx.action == :elapse, do: 120, else: 0)
      assert Repo.get!(World, ctx.world.id).fictional_time == 0

      assert length(
               LocalTime.entries(
                 Repo.all(from e in Event, where: e.experience_id == ^ctx.experience.id)
               )
             ) == 1

      cp = Repo.get_by!(Checkpoint, snapshot_id: ctx.snapshot.id)
      assert {:ok, replayed} = Replay.restore(ctx.owner, ctx.world.id, cp.id)
      assert replayed == working(ctx)
    end
  end

  test "a declared positive total with zero action time cannot pass the old publication path",
       ctx do
    declaration =
      declaration(ctx, %{
        "elapsed_seconds" => 7200,
        "outcome" => "failed",
        "reason" => "Off-platform errand"
      })

    assert {:ok, _} = control(ctx, {:finish, declaration}, 0, "finish")

    assert {:error, :time_reconciliation_unavailable} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    event =
      Repo.one!(
        from e in Event,
          where:
            e.experience_id == ^ctx.experience.id and
              e.core_event_id ==
                ^Repo.get!(Experience, ctx.experience.id).completion["completion_id"]
      )

    assert {:ok, %{result: result}} = Codec.load(event.event)
    assert result["declaration"] == declaration
  end

  defp control(ctx, action, revision, request),
    do:
      Runtime.call(
        ctx.owner,
        ctx.world.id,
        {:status, ctx.experience.id, action, revision, request}
      )

  defp declaration(ctx, attrs) do
    {:ok, basis} = Seals.basis(Repo.get!(Experience, ctx.experience.id))
    Map.put(attrs, "basis", basis)
  end

  defp working(ctx) do
    {:ok, scene} = Snapshots.load(Repo.get!(Snapshot, ctx.snapshot.id))
    scene
  end
end
