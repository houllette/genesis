defmodule GenesisWeb.NetworkLiveTest do
  use GenesisWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Genesis.WorldFixtures
  import Genesis.AccountsFixtures
  alias Genesis.Accounts.Scope
  alias Genesis.{Content, WorldNetwork, Worlds}
  alias Genesis.Content.NetworkCatalog
  alias Genesis.Engine.WorldSupervisor

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

    {:ok, %{"zone_id" => docks}} =
      Content.create_zone(ctx.owner, ctx.world.id, %{"name" => "Docks"}, "docks")

    {:ok, Map.merge(ctx, %{conn: log_in_user(conn, ctx.owner.user), docks: docks})}
  end

  test "GM connects places, edits condition, checks capacity, and registers the existing institution",
       ctx do
    {:ok, workspace, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}")
    assert has_element?(workspace, "#open-network[href='/worlds/#{ctx.world.id}/connections']")
    {:ok, page, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/connections")
    refute has_element?(page, "#network-form")
    assert has_element?(page, "#network-boundary", "not enabled")
    page |> element("#network-new") |> render_click()

    page
    |> form("#network-form",
      record: %{from: "bridge", to: ctx.docks, capacity: "4", visibility: "public"}
    )
    |> render_submit()

    assert has_element?(page, "#network-connections article", "Docks")
    refute has_element?(page, "#network-form")

    page
    |> form("#network-check", check: %{from: "bridge", to: ctx.docks, size: "5"})
    |> render_submit()

    assert has_element?(page, "#network-assessment", "exceeds")

    page
    |> form("#network-check", check: %{from: "bridge", to: ctx.docks, size: "4"})
    |> render_submit()

    assert has_element?(page, "#network-assessment", "nobody has moved")
    page |> element("#network-connections button") |> render_click()
    refute has_element?(page, "#record_from")
    page |> form("#network-form", record: %{condition: "damaged"}) |> render_submit()
    assert has_element?(page, "#network-connections article", "Damaged")

    page
    |> form("#network-check", check: %{from: "bridge", to: ctx.docks, size: "1"})
    |> render_submit()

    assert has_element?(page, "#network-assessment", "block passage")

    id = NetworkCatalog.institution_id(ctx.world.id, "bridge", "settlement")
    assert has_element?(page, "#jurisdiction-#{id}", "Register reach")
    page |> element("#jurisdiction-#{id}") |> render_click()

    page
    |> form("#network-form", record: %{zones: ["bridge", ctx.docks], visibility: "public"})
    |> render_submit()

    assert has_element?(page, "#network-institutions article", "Declared reach")

    assert has_element?(
             page,
             "#institution-home-#{id}[href='/worlds/#{ctx.world.id}/places/bridge/resources']"
           )

    assert {:ok, %{institutions: [%{registered: true, zones: zones}]}} =
             WorldNetwork.view(ctx.owner, ctx.world.id)

    assert Enum.sort(zones) == Enum.sort(["bridge", ctx.docks])
  end

  test "public preview filters private edges and editors; live role downgrade clears them", ctx do
    builder = Scope.for_user(user_fixture())
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "builder", "builder")

    {:ok, _} =
      WorldNetwork.save(
        ctx.owner,
        ctx.world.id,
        %{generation: 0, revision: 0},
        connection(ctx),
        "secret"
      )

    conn = log_in_user(build_conn(), builder.user)
    {:ok, page, _} = live(conn, ~p"/worlds/#{ctx.world.id}/connections")
    assert has_element?(page, "#network-connections article")
    page |> element("#network-preview") |> render_click()
    refute has_element?(page, "#network-connections article")
    refute has_element?(page, "#network-new")
    page |> element("#network-preview") |> render_click()
    page |> element("#network-connections button") |> render_click()
    assert has_element?(page, "#network-form")
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "viewer", "downgrade")
    send(page.pid, {:world_changed, ctx.world.id, 999})
    refute has_element?(page, "#network-connections article")
    refute has_element?(page, "#network-institutions article")
    refute has_element?(page, "#network-form")
    refute has_element?(page, "#network-new")

    assert {:error, :route_unavailable} =
             WorldNetwork.assess(builder, ctx.world.id, "bridge", ctx.docks, 1)
  end

  test "stale or delayed editors cannot be rebound to a newer network", ctx do
    {:ok, page, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/connections")
    page |> element("#network-new") |> render_click()

    old_request =
      page
      |> element("#network-form input[name='editor_request']")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("value")
      |> hd()

    page |> element("#network-cancel") |> render_click()
    page |> element("#network-new") |> render_click()

    render_submit(page, "save", %{
      "editor_request" => old_request,
      "record" => Map.delete(connection(ctx), "type")
    })

    assert {:ok, %{connections: []}} = WorldNetwork.view(ctx.owner, ctx.world.id)

    {:ok, _} =
      WorldNetwork.save(
        ctx.owner,
        ctx.world.id,
        %{generation: 0, revision: 0},
        connection(ctx),
        "concurrent"
      )

    send(page.pid, {:world_changed, ctx.world.id, 999})
    assert has_element?(page, "#network-stale")
    assert has_element?(page, "#network-save[disabled]")
    # Submit the old bound form despite its disabled button, as a stale client could.
    page
    |> form("#network-form", record: %{from: "bridge", to: ctx.docks, capacity: "100"})
    |> render_submit()

    assert {:ok, %{revision: 1, connections: [%{"capacity" => 4}]}} =
             WorldNetwork.view(ctx.owner, ctx.world.id)
  end

  test "an active Experience makes network edits drafts only", ctx do
    _ctx = experience_fixture(ctx)
    {:ok, page, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/connections")
    assert has_element?(page, "#network-window")
    page |> element("#network-new") |> render_click()
    assert has_element?(page, "#network-save", "Save draft")
    page |> form("#network-form", record: %{from: "bridge", to: ctx.docks}) |> render_submit()
    refute has_element?(page, "#network-connections article")
    assert [%{kind: "network"}] = Content.list_drafts(ctx.owner, ctx.world.id)
    assert {:ok, %{connections: [], revision: 0}} = WorldNetwork.view(ctx.owner, ctx.world.id)
  end

  test "unauthenticated users are redirected at the existing authenticated route", ctx do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/worlds/#{ctx.world.id}/connections")
  end

  defp connection(ctx),
    do: %{
      "type" => "connection",
      "from" => "bridge",
      "to" => ctx.docks,
      "capacity" => 4,
      "condition" => "open",
      "visibility" => "gm"
    }
end
