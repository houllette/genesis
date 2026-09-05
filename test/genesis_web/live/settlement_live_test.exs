defmodule GenesisWeb.SettlementLiveTest do
  use GenesisWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Genesis.WorldFixtures
  import Genesis.AccountsFixtures
  alias Genesis.Accounts.Scope
  alias Genesis.Content
  alias Genesis.Core.Stock
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}
  alias Genesis.Persistence.{Snapshot, Snapshots}
  alias Genesis.{Repo, Worlds}

  setup %{conn: conn} do
    ctx = world_fixture(ruleset: "fantasy_local")

    start_supervised!(
      {WorldSupervisor,
       registry: Genesis.Engine.Registry,
       world_id: ctx.world.id,
       generation: ctx.world.generation,
       owner: self(),
       storage: :postgres}
    )

    {:ok, Map.put(ctx, :conn, log_in_user(conn, ctx.owner.user))}
  end

  test "GM builds a religious market, authors holdings and resolves NPC trade and aid without any player",
       ctx do
    {:ok, world, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}")

    {:ok, place, _} =
      world
      |> form("#new-zone-form",
        zone: %{name: "Relief quay", description: "The grain boats arrive here."}
      )
      |> render_submit()
      |> follow_redirect(ctx.conn)

    for name <- ["Edda", "Tess"] do
      place |> form("#record-form", record: %{name: name}) |> render_submit()
      assert has_element?(place, "#actors article", name)
    end

    zone = Enum.find(Content.list_zones(ctx.owner, ctx.world.id), &(&1.name == "Relief quay"))
    {:ok, view} = Content.view(ctx.owner, ctx.world.id, zone.id)
    merchant = Enum.find(view.actors, &(&1.name == "Edda")).id
    representative = Enum.find(view.actors, &(&1.name == "Tess")).id

    {:ok, resources, _} =
      place |> element("#place-resources") |> render_click() |> follow_redirect(ctx.conn)

    resources
    |> form("#settlement-form",
      settlement: %{
        name: "Lantern relief",
        merchant_id: merchant,
        representative_id: representative,
        profile: "temple_market"
      }
    )
    |> render_submit()

    assert has_element?(resources, "#settlement-summary", "Lantern relief")

    for {owner, commodity, quantity} <- [
          {merchant, "grain", 12},
          {merchant, "coin", 100},
          {representative, "coin", 100}
        ] do
      resources
      |> form("#stock-form",
        stock: %{
          owner_id: owner,
          commodity: commodity,
          quantity: quantity,
          reason: "Opening allocation"
        }
      )
      |> render_submit()

      assert has_element?(resources, "#flash-info", "Saved with an audit record")
    end

    assert has_element?(resources, "#market-grain", "12")
    {:ok, campaign, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/campaigns/#{ctx.campaign.id}")

    {:ok, experience, _} =
      campaign
      |> form("#experience-form", experience: %{name: "Relief day", zone_id: zone.id})
      |> render_submit()
      |> follow_redirect(ctx.conn)

    experience |> element("#start-experience") |> render_click()

    {:ok, working, _} =
      experience
      |> element("#experience-resources")
      |> render_click()
      |> follow_redirect(ctx.conn)

    assert has_element?(working, "#resource-scope", "Working")
    quote(working, representative, "buy", merchant, 2)
    assert has_element?(working, "#local-quote", "20 minor units")
    assert has_element?(working, "#market-grain", "12")
    working |> element("#confirm-local-action") |> render_click()
    assert has_element?(working, "#market-grain", "10")
    quote(working, merchant, "produce", "mill", 1)
    working |> element("#confirm-local-action") |> render_click()
    quote(working, merchant, "affiliate", representative)
    working |> element("#confirm-local-action") |> render_click()
    assert has_element?(working, "#institution-records article", "pending")
    quote(working, merchant, "offer", representative, 1)
    working |> element("#confirm-local-action") |> render_click()
    assert has_element?(working, "#institution-records article", "fulfilled")
    quote(working, merchant, "aid", representative)
    working |> element("#confirm-local-action") |> render_click()
    assert has_element?(working, "#institution-records article", "redeemed")
    assert has_element?(working, "#resource-history article", "Redeem the fulfilled obligation")
    {:ok, published} = Content.view(ctx.owner, ctx.world.id, zone.id)
    assert published.settlement["available_grain"] == 12
    resources |> element("#reopen-resource-editors") |> render_click()

    resources
    |> form("#stock-form",
      stock: %{owner_id: merchant, commodity: "grain", quantity: 500, reason: "Future supply"}
    )
    |> render_submit()

    assert has_element?(resources, "#flash-info", "Draft")
    assert has_element?(resources, "#market-grain", "12")
  end

  test "stale resource editors require reopening and disabling live mechanics is refused", ctx do
    path = ~p"/worlds/#{ctx.world.id}/places/bridge/resources"
    {:ok, current, _} = live(ctx.conn, path)
    {:ok, stale, _} = live(ctx.conn, path)
    current |> form("#settlement-form", settlement: %{price: 12}) |> render_submit()
    stale |> form("#settlement-form", settlement: %{price: 99}) |> render_submit()
    assert has_element?(stale, "#flash-error", "Reopen the editors")
    stale |> element("#reopen-resource-editors") |> render_click()
    assert has_element?(stale, "input[name='settlement[price]'][value='12']")
    stale |> form("#settlement-form", settlement: %{enabled: false}) |> render_submit()
    assert has_element?(stale, "#flash-error", "Live holdings")
    assert has_element?(stale, "#settlement-summary", "Enabled")
  end

  test "a changed quote is declined without spending and the same pending quote survives pause and resume",
       ctx do
    ctx = experience_fixture(ctx)

    {:ok, working, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/resources")

    # A legitimate operator action changes the stock consulted by the pending quote.
    quote(working, "moll", "produce", "mill", 1)
    {:ok, actor} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "moll")

    {:ok, quote} =
      Session.propose(actor, "loss", %{type: "disrupt", target_id: "moll", quantity: 1})

    {:ok, _} = Session.confirm(actor, "loss", quote.id)
    working |> element("#confirm-local-action") |> render_click()
    assert has_element?(working, "#flash-error", "changed")
    {:ok, state} = Repo.get!(Snapshot, ctx.snapshot.id) |> Snapshots.load()
    assert Stock.balance(state, "moll", "grain") == 11
    assert Stock.balance(state, "moll", "ration") == 0
    quote(working, "moll", "produce", "mill", 1)

    {:ok, paused} =
      Runtime.call(
        ctx.owner,
        ctx.world.id,
        {:status, ctx.experience.id, :pause, state.revision, "pause"}
      )

    assert paused["status"] == "paused"
    {:ok, snapshot} = Repo.get!(Snapshot, ctx.snapshot.id) |> Snapshots.load()

    {:ok, _} =
      Runtime.call(
        ctx.owner,
        ctx.world.id,
        {:status, ctx.experience.id, :resume, snapshot.revision, "resume"}
      )

    working |> element("#confirm-local-action") |> render_click()
    assert has_element?(working, "#flash-info", "Saved once")
    {:ok, final} = Repo.get!(Snapshot, ctx.snapshot.id) |> Snapshots.load()
    assert Stock.balance(final, "moll", "ration") == 1
    assert final.elapsed == 0
  end

  test "viewer and foreign-world routes reveal neither treasury nor institutional records", ctx do
    viewer = Scope.for_user(user_fixture())
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, viewer.user.id, "viewer")
    viewer_conn = build_conn() |> log_in_user(viewer.user)

    assert {:error, {:live_redirect, %{to: "/worlds"}}} =
             live(viewer_conn, ~p"/worlds/#{ctx.world.id}/places/bridge/resources")

    assert {:error, {:live_redirect, %{to: "/worlds"}}} =
             live(ctx.conn, ~p"/worlds/#{Ecto.UUID.generate()}/places/bridge/resources")

    {:ok, preview} = Content.preview(ctx.owner, ctx.world.id, "bridge")
    refute Enum.any?(preview.items, &(&1.commodity == "coin"))
    refute Map.has_key?(preview.settlement, "witnessing")
  end

  test "native secular preset settles finite barter and refuses currency without pretending to trade",
       ctx do
    other = world_fixture(ruleset: "cyberpunk_local", profile: "mutual_aid")

    start_supervised!(
      {WorldSupervisor,
       registry: Genesis.Engine.Registry,
       world_id: other.world.id,
       generation: other.world.generation,
       owner: self(),
       storage: :postgres},
      id: :other_tree
    )

    other = experience_fixture(other)
    conn = log_in_user(ctx.conn, other.owner.user)

    {:ok, working, _} =
      live(conn, ~p"/worlds/#{other.world.id}/experiences/#{other.experience.id}/resources")

    assert has_element?(working, "#settlement-summary", "secular")
    quote(working, "reed", "buy", "moll", 1)
    assert has_element?(working, "#flash-error", "barter community")
    refute has_element?(working, "#local-quote")
    quote(working, "reed", "produce", "mill", 1)
    working |> element("#confirm-local-action") |> render_click()
    quote(working, "reed", "barter", "moll", 1)
    assert has_element?(working, "#local-quote", "Offer 1 ration for 2 grain")
    working |> element("#confirm-local-action") |> render_click()
    assert has_element?(working, "#flash-info", "Saved once")
    {:ok, state} = Repo.get!(Snapshot, other.snapshot.id) |> Snapshots.load()
    assert Stock.balance(state, "reed", "grain") == 4
    assert Stock.balance(state, "reed", "ration") == 0
    assert Stock.balance(state, "moll", "grain") == 10
    assert Stock.balance(state, "moll", "ration") == 1
    assert Stock.balance(state, "reed", "coin") == 0
  end

  defp quote(view, actor, type, target, quantity \\ nil) do
    view |> form("#local-action-form", command: %{type: type}) |> render_change()
    attrs = %{actor_id: actor, type: type, target_id: target}
    attrs = if quantity, do: Map.put(attrs, :quantity, quantity), else: attrs
    view |> form("#local-action-form", command: attrs) |> render_submit()
  end
end
