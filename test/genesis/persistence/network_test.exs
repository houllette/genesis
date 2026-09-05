defmodule Genesis.Persistence.NetworkTest do
  use Genesis.DataCase, async: false
  import Genesis.AccountsFixtures
  import Genesis.WorldFixtures
  alias Genesis.Accounts.Scope, as: UserScope
  alias Genesis.Content
  alias Genesis.Content.{Atlas, NetworkCatalog}
  alias Genesis.Core.{Context, Stock}
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}

  alias Genesis.Persistence.{
    Codec,
    Draft,
    Event,
    Network,
    Outbox,
    Receipt,
    Snapshot,
    Snapshots,
    World
  }

  alias Genesis.WorldNetwork

  setup do
    ctx = world_fixture(ruleset: "fantasy_local", zero_duration: true)

    start_supervised!(
      {WorldSupervisor,
       registry: Genesis.Engine.Registry,
       world_id: ctx.world.id,
       generation: ctx.world.generation,
       owner: self(),
       storage: :postgres,
       observer: self()}
    )

    assert_receive {:genesis_world_started, _}

    {:ok, %{"zone_id" => docks}} =
      Content.create_zone(ctx.owner, ctx.world.id, %{"name" => "Docks"}, "docks")

    {:ok, %{"zone_id" => ridge}} =
      Content.create_zone(ctx.owner, ctx.world.id, %{"name" => "Ridge"}, "ridge")

    {:ok, Map.merge(ctx, %{docks: docks, ridge: ridge})}
  end

  test "the World owner durably connects existing zones", ctx do
    command = %{
      "type" => "connection",
      "from" => "bridge",
      "to" => ctx.docks,
      "condition" => "open",
      "capacity" => 4,
      "visibility" => "public"
    }

    assert {:ok, %{"status" => "published", "revision" => 1}} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:network_save, expected(ctx, 0), command, "bridge-docks"}
             )

    assert {:ok, %{connections: [edge], zones: zones}} =
             WorldNetwork.view(ctx.owner, ctx.world.id)

    assert edge == Map.delete(command, "type")
    assert length(zones) == 3

    assert {:ok, %{"revision" => 2}} =
             save(ctx, 1, connection(ctx.docks, ctx.ridge), "docks-ridge")

    assert :ok = WorldNetwork.assess(ctx.owner, ctx.world.id, "bridge", ctx.docks, 4)

    assert {:error, :capacity_exceeded} =
             WorldNetwork.assess(ctx.owner, ctx.world.id, "bridge", ctx.docks, 5)

    assert {:error, :route_unavailable} =
             WorldNetwork.assess(ctx.owner, ctx.world.id, ctx.docks, "bridge", 1)

    assert {:ok, _} = save(ctx, 2, %{command | "condition" => "damaged"}, "damage")

    assert {:error, :route_unavailable} =
             WorldNetwork.assess(ctx.owner, ctx.world.id, "bridge", ctx.docks, 1)

    assert Repo.get!(Snapshot, ctx.published.id).digest == ctx.published.digest
    assert Repo.get!(World, ctx.world.id).fictional_time == ctx.world.fictional_time
  end

  test "receipts bind payloads, authorize first, and survive a World restart", ctx do
    command = connection("bridge", ctx.docks)
    assert {:ok, result} = save(ctx, 0, command, "connect")
    events = Repo.aggregate(Event, :count)
    assert {:ok, ^result} = save(ctx, 0, command, "connect")
    assert {:error, :request_conflict} = save(ctx, 0, %{command | "capacity" => 2}, "connect")
    assert Repo.aggregate(Event, :count) == events

    world =
      GenServer.whereis(
        Genesis.Engine.Supervisor.via(Genesis.Engine.Registry, {:world, ctx.world.id})
      )

    ref = Process.monitor(world)
    :ok = GenServer.stop(world, :normal)
    assert_receive {:DOWN, ^ref, :process, ^world, :normal}
    assert_receive {:genesis_world_started, restarted}
    refute restarted == world
    assert {:ok, ^result} = save(ctx, 0, command, "connect")
    assert Repo.aggregate(Event, :count) == events
    assert {:ok, %{connections: [_], revision: 1}} = WorldNetwork.view(ctx.owner, ctx.world.id)

    builder = UserScope.for_user(user_fixture())

    {:ok, _} =
      Genesis.Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "builder", "builder")

    assert {:ok, _} =
             WorldNetwork.save(builder, ctx.world.id, expected(ctx, 1), command, "builder-save")

    {:ok, _} =
      Genesis.Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "viewer", "downgrade")

    assert {:error, :unauthorized} =
             WorldNetwork.save(builder, ctx.world.id, expected(ctx, 1), command, "builder-save")
  end

  test "registration keeps the atlas identity, affiliations, stock, old receipts and snapshot bytes",
       ctx do
    assert {:ok, %{institutions: [local]}} = WorldNetwork.view(ctx.owner, ctx.world.id)
    refute local.registered
    id = NetworkCatalog.institution_id(ctx.world.id, "bridge", "settlement")
    assert local.id == id
    old_receipts = Repo.all(Receipt)
    assert {:ok, _} = save(ctx, 0, jurisdiction(id, ["bridge", ctx.docks]), "register")
    assert {:ok, %{institutions: [registered]}} = WorldNetwork.view(ctx.owner, ctx.world.id)
    assert registered.registered
    assert registered.id == id
    assert registered.zones == ["bridge", ctx.docks]

    assert {:ok, %{record: %{id: reference}}} =
             Atlas.get(ctx.owner, ctx.world.id, "institution:" <> id)

    assert reference == "institution:" <> registered.id
    assert Repo.get!(Snapshot, ctx.published.id) == ctx.published
    assert Enum.all?(old_receipts, &(Repo.get!(Receipt, &1.id) == &1))

    attrs = Map.put(Genesis.SettlementFixtures.configuration(), "name", "Renamed relief guild")

    assert {:ok, _} =
             Content.curate(
               ctx.owner,
               ctx.world.id,
               "bridge",
               ctx.seed.revision,
               "settlement",
               attrs,
               "rename"
             )

    assert {:ok, %{institutions: [%{id: ^id, name: "Renamed relief guild"}]}} =
             WorldNetwork.view(ctx.owner, ctx.world.id)

    row = Repo.get_by!(Network, world_id: ctx.world.id)
    refute Map.has_key?(row.data["institutions"][id], "name")
    refute Map.has_key?(row.data["institutions"][id], "stock")
  end

  test "private connections and hidden institutional endpoints never enter the public projection",
       ctx do
    command = %{connection("bridge", ctx.docks) | "visibility" => "gm"}
    id = NetworkCatalog.institution_id(ctx.world.id, "bridge", "settlement")
    assert {:ok, _} = save(ctx, 0, command, "secret")
    assert {:ok, _} = save(ctx, 1, jurisdiction(id, ["bridge", ctx.docks]), "public-jurisdiction")

    assert {:ok, %{connections: [], institutions: [_]}} =
             WorldNetwork.view(ctx.owner, ctx.world.id, public: true)

    assert {:ok, _} =
             Content.curate(
               ctx.owner,
               ctx.world.id,
               "bridge",
               ctx.seed.revision,
               "reed",
               %{"kind" => "npc", "name" => "Secret representative", "visibility" => "private"},
               "hide"
             )

    assert {:ok, %{connections: [], institutions: []}} =
             WorldNetwork.view(ctx.owner, ctx.world.id, public: true)

    outsider = UserScope.for_user(user_fixture())
    assert {:error, :unauthorized} = WorldNetwork.view(outsider, ctx.world.id)
  end

  test "open-window edits remain drafts and do not change the base or working snapshots", ctx do
    command = connection("bridge", ctx.docks)
    assert {:ok, _} = save(ctx, 0, command, "original")
    ctx = experience_fixture(ctx)
    before = Repo.get_by!(Network, world_id: ctx.world.id)
    world = Repo.get!(World, ctx.world.id)

    assert {:ok, %{"status" => "draft"} = result} =
             save(ctx, 1, %{command | "condition" => "closed"}, "draft")

    assert {:ok, ^result} = save(ctx, 1, %{command | "condition" => "closed"}, "draft")
    assert Repo.get_by!(Network, world_id: ctx.world.id) == before
    assert Repo.get!(Snapshot, ctx.snapshot.id) == ctx.snapshot
    assert Repo.get!(World, ctx.world.id).revision == world.revision
    assert [%{kind: "network", attrs: %{"network_revision" => 1}}] = Repo.all(Draft)
    assert :ok = WorldNetwork.assess(ctx.owner, ctx.world.id, "bridge", ctx.docks, 1)
  end

  test "snapshot, audit, receipt and outbox roll back together", ctx do
    count = Repo.aggregate(Event, :count)

    assert {:error, :injected_failure} =
             Repo.transact(fn ->
               assert {:ok, _} =
                        WorldNetwork.persist(
                          ctx.owner,
                          ctx.world.id,
                          expected(ctx, 0),
                          connection("bridge", ctx.docks),
                          "rollback"
                        )

               assert Repo.aggregate(Network, :count) == 1
               {:error, :injected_failure}
             end)

    assert Repo.aggregate(Network, :count) == 0
    assert Repo.aggregate(Event, :count) == count
    assert {:ok, %{"revision" => 1}} = save(ctx, 0, connection("bridge", ctx.docks), "rollback")
    event = Repo.one!(from e in Event, where: e.scope_key == "network:0")

    assert {:ok, %{"before" => %{"connections" => []}, "after" => %{"connections" => [_]}}} =
             Codec.load(event.event)

    assert Repo.get_by!(Outbox, event_id: event.id)
    assert_enqueued(worker: Genesis.Persistence.DeliverEvent)
  end

  test "stale authors, foreign endpoints, malformed commands and discarded generations cannot write",
       ctx do
    command = connection("bridge", ctx.docks)
    assert {:ok, _} = save(ctx, 0, command, "winner")
    assert {:error, :stale_revision} = save(ctx, 0, command, "stale")

    assert {:error, :stale_generation} =
             WorldNetwork.save(
               ctx.owner,
               ctx.world.id,
               %{generation: 99, revision: 1},
               command,
               "future"
             )

    assert {:error, :invalid_connection} =
             save(ctx, 1, %{command | "to" => "foreign-zone"}, "foreign")

    assert {:error, :unsupported_operation} = save(ctx, 1, %{"type" => "travel"}, "travel")
    assert {:error, :invalid_format} = save(ctx, 1, %{"type" => self()}, "malformed")
    assert Repo.get_by!(Network, world_id: ctx.world.id).revision == 1

    row = Repo.get_by!(Network, world_id: ctx.world.id)
    Repo.update!(Ecto.Changeset.change(row, data: %{row.data | "version" => 99}))
    assert {:error, :invalid_network} = WorldNetwork.view(ctx.owner, ctx.world.id)
    assert {:error, :invalid_network} = save(ctx, 1, command, "cannot-repair-by-overwrite")
  end

  test "registering an institution after incorporation preserves sourced membership and paid offerings",
       ctx do
    {:ok, _} =
      Genesis.Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara"
      )

    ctx = experience_fixture(ctx)
    {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")

    for {type, extra} <- [{"affiliate", %{}}, {"offer", %{quantity: 1}}] do
      intent = Map.merge(%{type: type, target_id: "reed"}, extra)
      assert {:ok, quote} = Session.propose(session, type, intent)
      assert {:ok, _} = Session.confirm(session, type, quote.id)
    end

    {:ok, view} = Session.view(session)

    assert {:ok, _} =
             Runtime.call(
               ctx.owner,
               ctx.world.id,
               {:status, ctx.experience.id, :ready, view.revision, "ready"}
             )

    assert {:ok, preview} =
             Runtime.call(ctx.owner, ctx.world.id, {:preview_incorporation, ctx.experience.id})

    assert {:ok, _} = Runtime.call(ctx.owner, ctx.world.id, {:incorporate, preview.id, "publish"})
    before = Repo.get!(Snapshot, ctx.published.id)
    {:ok, state} = Snapshots.load(before)
    assert Context.institution(state, "mara", "reed").eligible
    assert Stock.balance(state, "reed", "ration") == 1

    sources =
      Repo.all(
        from e in Event, where: e.world_id == ^ctx.world.id and not is_nil(e.source_event_id)
      )

    assert length(sources) == 2
    receipts = Repo.all(Receipt)

    id = NetworkCatalog.institution_id(ctx.world.id, "bridge", "settlement")

    assert {:ok, %{"status" => "published"}} =
             save(ctx, 0, jurisdiction(id, ["bridge", ctx.docks]), "register-after-play")

    assert Repo.get!(Snapshot, before.id) == before
    assert Enum.all?(sources, &(Repo.get!(Event, &1.id) == &1))
    assert Enum.all?(receipts, &(Repo.get!(Receipt, &1.id) == &1))
  end

  defp expected(ctx, revision), do: %{generation: ctx.world.generation, revision: revision}

  defp save(ctx, revision, command, request),
    do: WorldNetwork.save(ctx.owner, ctx.world.id, expected(ctx, revision), command, request)

  defp connection(from, to),
    do: %{
      "type" => "connection",
      "from" => from,
      "to" => to,
      "condition" => "open",
      "capacity" => 4,
      "visibility" => "public"
    }

  defp jurisdiction(id, zones),
    do: %{
      "type" => "jurisdiction",
      "institution_id" => id,
      "zones" => zones,
      "visibility" => "public"
    }
end
