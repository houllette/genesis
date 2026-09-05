defmodule Genesis.Persistence.SettlementTest do
  use Genesis.DataCase, async: false
  @moduletag capture_log: true
  alias Genesis.{Campaigns, Content, Experiences}
  alias Genesis.Core.{Context, Stock}
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}

  alias Genesis.Persistence.{
    Checkpoint,
    Codec,
    Event,
    History,
    Receipt,
    Replay,
    Snapshot,
    Snapshots
  }

  import Genesis.WorldFixtures

  test "connected local deeds publish once, replay without production and remain in the next campaign" do
    for profile <- ["temple_market", "mutual_aid"] do
      ctx = prepared(profile: profile)
      {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
      trade = if profile == "temple_market", do: "buy", else: "barter"
      assert {:ok, _} = execute(session, trade, "moll", %{quantity: 1})
      assert {:ok, _} = execute(session, "produce", "mill", %{quantity: 1})
      assert {:ok, _} = execute(session, "affiliate", "reed")
      assert {:ok, _} = execute(session, "offer", "reed", %{quantity: 1})
      assert {:ok, current} = Session.view(session)
      assert current.elapsed == 0
      assert {:ok, initial} = Snapshots.load(ctx.published)
      assert Stock.balance(initial, "reed", "ration") == 0

      assert {:ok, _} =
               Runtime.call(
                 ctx.owner,
                 ctx.world.id,
                 {:status, ctx.experience.id, :ready, current.revision, "ready"}
               )

      assert {:ok, preview} =
               Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

      assert {:ok, published} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert {:ok, ^published} =
               Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})

      assert {:ok, canonical} = Repo.get!(Snapshot, ctx.published.id) |> Snapshots.load()
      assert Stock.balance(canonical, "reed", "ration") == 1
      assert Context.institution(canonical, "mara", "reed").eligible

      assert Repo.aggregate(
               from(e in Event,
                 where: e.world_id == ^ctx.world.id and not is_nil(e.source_event_id)
               ),
               :count
             ) == 4

      checkpoint =
        Repo.one!(
          from c in Checkpoint,
            where: c.snapshot_id == ^ctx.published.id,
            order_by: c.cursor,
            limit: 1
        )

      assert {:ok, ^canonical} = Replay.restore(ctx.owner, ctx.world.id, checkpoint.id)

      # A World restart loses grants but not goods or the institution's sourced promise.
      tree_id = {:world_tree, ctx.world.id}
      assert :ok = stop_supervised(tree_id)
      start_tree(ctx)

      {:ok, later_campaign} =
        Campaigns.create_campaign(
          ctx.owner,
          ctx.world.id,
          %{"name" => "Returning visitors"},
          "later"
        )

      {:ok, _} =
        Campaigns.bind_character(
          ctx.owner,
          ctx.world.id,
          later_campaign.id,
          ctx.owner.user.id,
          "mara"
        )

      {:ok, next_exp} =
        Experiences.create(
          ctx.owner,
          ctx.world.id,
          later_campaign.id,
          %{"name" => "Return", "zone_id" => "bridge", "participants" => ["mara"]},
          "return"
        )

      {:ok, _} = Experiences.start(ctx.owner, ctx.world.id, next_exp.id, 0)
      {:ok, later} = Runtime.attach(ctx.owner, ctx.world.id, next_exp.id, "mara")
      assert {:ok, _} = execute(later, "aid", "reed")

      assert {:error, :aid_unavailable} =
               Session.propose(later, "again", %{type: "aid", target_id: "reed"})

      {:ok, later_state} = Repo.get_by!(Snapshot, experience_id: next_exp.id) |> Snapshots.load()

      assert Stock.balance(later_state, "reed", "grain") ==
               Stock.balance(canonical, "reed", "grain") - 1

      assert :ok = stop_supervised(tree_id)
    end
  end

  test "two confirmed buyers race for the last item; the loser pays nothing and another experience cannot copy claimed stock" do
    ctx = prepared(merchant_stock: 1, participants: ["mara", "courier"])

    {:ok, other} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "Other", "zone_id" => "bridge"},
        "other"
      )

    assert {:error, :claimed} = Experiences.start(ctx.owner, ctx.world.id, other.id, 0)
    tasks = start_supervised!(Task.Supervisor)
    parent = self()

    buyers =
      for actor <- ["mara", "courier"] do
        Task.Supervisor.async_nolink(tasks, fn ->
          {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, actor)

          {:ok, quote} =
            Session.propose(session, "last", %{type: "buy", target_id: "moll", quantity: 1})

          send(parent, {:quoted, self()})

          receive do
            :settle -> {actor, Session.confirm(session, actor <> "-last", quote.id)}
          end
        end)
      end

    for _ <- buyers, do: assert_receive({:quoted, _})
    Enum.each(buyers, &send(&1.pid, :settle))
    results = Enum.map(buyers, &Task.await/1)
    assert Enum.count(results, &match?({_, {:ok, _}}, &1)) == 1
    assert Enum.count(results, &match?({_, {:error, :stale_proposal}}, &1)) == 1
    {:ok, state} = Repo.get!(Snapshot, ctx.snapshot.id) |> Snapshots.load()
    assert Stock.balance(state, "moll", "grain") == 0
    assert Stock.balance(state, "moll", "coin") == 220

    assert Enum.sort(Enum.map(["mara", "courier"], &Stock.balance(state, &1, "coin"))) == [
             80,
             100
           ]

    assert Repo.aggregate(
             from(e in Event,
               where: e.experience_id == ^ctx.experience.id and not is_nil(e.actor_id)
             ),
             :count
           ) == 1
  end

  for boundary <- [:before_commit, :after_commit, :after_install] do
    @tag boundary: boundary
    test "commerce crash at #{boundary} never charges or delivers twice", tags do
      fault = fn stage -> if stage == tags.boundary, do: exit({:injected, stage}), else: :ok end
      ctx = prepared(zone_opts: [fault: fault])
      {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

      {:ok, quote} =
        Session.propose(session, "quote", %{type: "buy", target_id: "moll", quantity: 2})

      assert catch_exit(Session.confirm(session, "purchase", quote.id))
      {:ok, after_crash} = Repo.get!(Snapshot, ctx.snapshot.id) |> Snapshots.load()
      committed = if tags.boundary == :before_commit, do: 0, else: 1
      assert Stock.balance(after_crash, "mara", "coin") == 100 - committed * 20
      assert Stock.balance(after_crash, "mara", "grain") == 2 + committed * 2

      world =
        GenServer.whereis(
          Genesis.Engine.Supervisor.via(Genesis.Engine.Registry, {:world, ctx.world.id})
        )

      :sys.replace_state(world, &%{&1 | zone_opts: []})
      {:ok, replacement} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

      if committed == 0 do
        assert {:error, :unavailable} = Session.confirm(replacement, "purchase", quote.id)

        {:ok, same_quote} =
          Session.propose(replacement, "quote", %{type: "buy", target_id: "moll", quantity: 2})

        assert same_quote.id == quote.id
      end

      assert {:ok, result} = Session.confirm(replacement, "purchase", quote.id)
      assert {:ok, retry} = Session.confirm(replacement, "purchase", quote.id)
      assert retry.effects == result.effects

      assert Repo.aggregate(
               from(r in Receipt,
                 where: r.world_id == ^ctx.world.id and r.request_id == "purchase"
               ),
               :count
             ) == 1

      {:ok, final} = Repo.get!(Snapshot, ctx.snapshot.id) |> Snapshots.load()
      assert Stock.balance(final, "mara", "coin") == 80
      assert Stock.balance(final, "mara", "grain") == 4
    end
  end

  test "canonical resource authoring records sources, preserves window bases and refuses unsafe migrations" do
    ctx = world_fixture(ruleset: "fantasy_local")
    start_tree(ctx)

    attrs = %{
      "kind" => "stock",
      "name" => "Copper",
      "commodity" => "coin",
      "owner_id" => "mara",
      "quantity" => 50,
      "reason" => "Correct opening allocation"
    }

    assert {:ok, _} =
             Content.curate(
               ctx.owner,
               ctx.world.id,
               "bridge",
               ctx.seed.revision,
               "mara-coin",
               attrs,
               "correct"
             )

    assert {:ok, state} = Repo.get!(Snapshot, ctx.published.id) |> Snapshots.load()
    assert Stock.balance(state, "mara", "coin") == 50

    record =
      Repo.one!(
        from e in Event, where: e.world_id == ^ctx.world.id, order_by: [desc: e.cursor], limit: 1
      )

    assert {:ok,
            %{accounting: %{"version" => 1, "delta" => -50, "kind" => "authorized_source_sink"}}} =
             Codec.load(record.event)

    ctx = experience_fixture(ctx)

    assert {:ok, %{"status" => "draft"}} =
             Content.curate(
               ctx.owner,
               ctx.world.id,
               "bridge",
               state.revision,
               "mara-coin",
               %{attrs | "quantity" => 60},
               "draft"
             )

    assert {:ok, unchanged} = Repo.get!(Snapshot, ctx.published.id) |> Snapshots.load()
    assert unchanged == state

    assert {:ok, %{events: events}} =
             History.page(ctx.owner, ctx.world.id, experience_id: ctx.experience.id)

    refute Enum.any?(events, &(&1.type == "buy"))
  end

  test "declining more than 64 quotes frees proposal capacity without reserving stock or writing events" do
    ctx = prepared([])
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

    for index <- 1..70 do
      id = "quote-#{index}"

      assert {:ok, quote} =
               Session.propose(session, id, %{type: "buy", target_id: "moll", quantity: 1})

      assert :ok = Session.cancel(session, quote.id)
    end

    assert {:ok, view} = Session.view(session)
    assert view.revision == 0
    assert view.settlement["available_grain"] == 12

    refute Repo.exists?(
             from e in Event,
               where: e.experience_id == ^ctx.experience.id and e.actor_id == "mara"
           )
  end

  test "a retired quote identity cannot be rebound to new terms and confirmed by a delayed old message" do
    ctx = prepared([])
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

    {:ok, old} =
      Session.propose(session, "reused-client-id", %{type: "buy", target_id: "moll", quantity: 1})

    assert :ok = Session.cancel(session, old.id)

    {:ok, replacement} =
      Session.propose(session, "reused-client-id", %{type: "buy", target_id: "moll", quantity: 5})

    refute replacement.id == old.id
    assert {:error, :unavailable} = Session.confirm(session, "old-confirmation", old.id)
    assert {:ok, state} = Repo.get!(Snapshot, ctx.snapshot.id) |> Snapshots.load()
    assert Stock.balance(state, "mara", "coin") == 100
  end

  defp prepared(opts) do
    ctx = world_fixture(Keyword.put(opts, :ruleset, "fantasy_local"))

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara"
      )

    # Admission precedes concurrent commands, so both legitimate participants are pinned.
    if "courier" in Keyword.get(opts, :participants, []),
      do:
        Campaigns.bind_character(
          ctx.owner,
          ctx.world.id,
          ctx.campaign.id,
          ctx.owner.user.id,
          "courier"
        )

    ctx = experience_fixture(ctx, opts)
    start_tree(ctx, Keyword.get(opts, :zone_opts, []))
    ctx
  end

  defp start_tree(ctx, zone_opts \\ []) do
    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: ctx.world.generation,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres,
       zone_opts: zone_opts},
      id: {:world_tree, ctx.world.id}
    )
  end

  defp execute(session, type, target, extra \\ %{}) do
    id = Ecto.UUID.generate()

    with {:ok, quote} <-
           Session.propose(session, id, Map.merge(%{type: type, target_id: target}, extra)),
         do: Session.confirm(session, id, quote.id)
  end
end
