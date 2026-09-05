defmodule Genesis.Persistence.IncorporationTest do
  use Genesis.DataCase, async: false
  @moduletag capture_log: true
  alias Genesis.Campaigns
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}
  alias Genesis.Experiences
  alias Genesis.Persistence.{Checkpoint, Claim, Event, Experience, Replay, Snapshot, Snapshots}
  import Genesis.WorldFixtures

  test "zero-duration outcome is incorporated once, keeps provenance through archive and changes a later campaign" do
    ctx = setup_experience(zero_duration: true)
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, _} = Session.propose(session, "help", %{type: "help", target_id: "moll"})
    {:ok, _} = Session.confirm(session, "help", "help")

    assert {:error, :unfinished_experiences} =
             Campaigns.archive(ctx.owner, ctx.world.id, ctx.campaign.id, 0)

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, :ready, 1, "ready"}
             )

    assert {:ok, preview} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    assert preview.elapsed_seconds == 0

    assert {:ok, result} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert {:ok, ^result} =
             Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

    assert {:error, :unauthorized} = Session.view(session)
    assert result["world_time"] == 0
    assert Repo.get!(Experience, ctx.experience.id).status == "incorporated"
    refute Repo.exists?(from c in Claim, where: c.experience_id == ^ctx.experience.id)

    event =
      Repo.one!(
        from e in Event, where: e.world_id == ^ctx.world.id and not is_nil(e.source_event_id)
      )

    {:ok, published} = ctx.published.id |> then(&Repo.get!(Snapshot, &1)) |> Snapshots.load()

    fact =
      Enum.find(Map.values(published.knowledge), &(&1.predicate == "helped" and &1.kind == :fact))

    assert fact.scope.kind == :published
    assert fact.source_ids == [event.core_event_id]

    checkpoint =
      Repo.one!(
        from c in Checkpoint,
          where: c.snapshot_id == ^ctx.published.id,
          order_by: c.cursor,
          limit: 1
      )

    assert {:ok, ^published} = Replay.restore(ctx.owner, ctx.world.id, checkpoint.id)
    assert {:ok, _archived} = Campaigns.archive(ctx.owner, ctx.world.id, ctx.campaign.id, 0)

    {:ok, campaign} =
      Campaigns.create_campaign(
        ctx.owner,
        ctx.world.id,
        %{"name" => "Later visitors"},
        "later-campaign"
      )

    {:ok, _} =
      Campaigns.bind_character(ctx.owner, ctx.world.id, campaign.id, ctx.owner.user.id, "mara")

    {:ok, exp} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        campaign.id,
        %{"name" => "Return", "zone_id" => "bridge", "participants" => ["mara"]},
        "later-experience"
      )

    {:ok, _} = Experiences.start(ctx.owner, ctx.world.id, exp.id, 0)
    {:ok, later} = Runtime.attach(ctx.owner, ctx.world.id, exp.id, "mara")
    {:ok, _} = Session.propose(later, "access", %{type: "access", target_id: "moll"})
    assert {:ok, changed} = Session.confirm(later, "access", "access")
    assert hd(changed.effects).result["outcome"] == "admitted"

    assert Repo.one!(from e in Event, where: e.id == ^event.id).source_event_id ==
             event.source_event_id
  end

  test "positive elapsed time is retained and cannot use the zero-duration publication proof" do
    ctx = setup_experience()
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
    {:ok, _} = Session.propose(session, "help", %{type: "help", target_id: "moll"})
    {:ok, _} = Session.confirm(session, "help", "help")

    {:ok, _} =
      Runtime.call(ctx.owner, ctx.world.id, {:status, ctx.experience.id, :ready, 1, "ready"})

    assert {:error, :time_reconciliation_unavailable} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    assert Repo.get!(Experience, ctx.experience.id).completion["elapsed_seconds"] == 60

    assert Repo.aggregate(from(c in Claim, where: c.experience_id == ^ctx.experience.id), :count) ==
             7

    assert {:ok, %{elapsed: 0}} = Snapshots.load(ctx.published)
  end

  for boundary <- [:before_commit, :after_commit, :after_install] do
    @tag boundary: boundary
    test "incorporation crash/retry at #{boundary} produces one source mapping", tags do
      ctx = setup_experience(zero_duration: true)
      {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

      {:ok, _} =
        Session.submit(session, %{
          id: "take",
          revision: 0,
          intent: %{type: "take", target_id: "ration"}
        })

      {:ok, _} =
        Runtime.call(ctx.owner, ctx.world.id, {:status, ctx.experience.id, :ready, 1, "ready"})

      {:ok, preview} =
        Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

      world =
        GenServer.whereis(
          Genesis.Engine.Supervisor.via(Genesis.Engine.Registry, {:world, ctx.world.id})
        )

      fault = fn stage -> if stage == tags.boundary, do: exit({:injected, stage}), else: :ok end
      :sys.replace_state(world, &%{&1 | zone_opts: [fault: fault]})

      assert {:error, :publication_interrupted} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      :sys.replace_state(world, &%{&1 | zone_opts: []})

      if tags.boundary == :before_commit do
        assert Repo.get!(Experience, ctx.experience.id).status == "ready"

        assert {:ok, %{id: id}} =
                 Runtime.call(
                   ctx.owner,
                   ctx.world.id,
                   {:preview_incorporation, ctx.experience.id}
                 )

        assert id == preview.id
      end

      assert {:ok, _} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert Repo.aggregate(
               from(e in Event,
                 where: e.world_id == ^ctx.world.id and not is_nil(e.source_event_id)
               ),
               :count
             ) == 1

      assert {:ok, final} = ctx.published.id |> then(&Repo.get!(Snapshot, &1)) |> Snapshots.load()
      assert final.items["ration"].owner == {:actor, "mara"}
      assert final.items["ration"].quantity == 2
    end
  end

  defp setup_experience(opts \\ []) do
    ctx = world_fixture(opts)

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

    ctx
  end
end
