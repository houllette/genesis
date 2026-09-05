defmodule GenesisWeb.AtlasLiveTest do
  use GenesisWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Genesis.WorldFixtures
  import Genesis.AccountsFixtures
  alias Genesis.Accounts.Scope
  alias Genesis.Content.Atlas
  alias Genesis.Engine.WorldSupervisor
  alias Genesis.Worlds

  setup %{conn: conn} do
    ctx = world_fixture()

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

  test "GM creates searchable lore and follows a live person link without another character copy",
       ctx do
    {:ok, page, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/atlas")
    refute has_element?(page, "#atlas-form")
    page |> element("#atlas-new") |> render_click()

    page
    |> form("#atlas-form",
      record: %{name: "River history", body: "A story of the flood", visibility: "public"}
    )
    |> render_submit()

    refute has_element?(page, "#atlas-form")
    assert has_element?(page, "#atlas-records article", "River history")
    page |> element("#atlas-new") |> render_click()
    page |> form("#atlas-form", record: %{kind: "relationship"}) |> render_change()

    page
    |> form("#atlas-form",
      record: %{
        name: "Moll at the bridge",
        source: "actor:moll",
        target: "zone:bridge",
        relation: "located_in",
        visibility: "public"
      }
    )
    |> render_submit()

    assert has_element?(page, "#atlas-records article", "Moll at the bridge")
    page |> element("button[phx-value-ref='actor:moll']") |> render_click()
    assert has_element?(page, "#atlas-owner[href='/worlds/#{ctx.world.id}/places/bridge']")
    refute has_element?(page, "#atlas-edit")
    assert has_element?(page, "#atlas-links", "Moll at the bridge")
    page |> element("#atlas-links button") |> render_click()
    assert has_element?(page, "#atlas-edit")
  end

  test "opening an editor from filtered results retains both selected endpoints", ctx do
    attrs = %{
      "kind" => "relationship",
      "name" => "A connection",
      "source" => "actor:moll",
      "target" => "zone:bridge",
      "relation" => "located_in",
      "visibility" => "public"
    }

    {:ok, record} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "connection")
    {:ok, page, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/atlas")
    page |> form("#atlas-search", search: %{query: "A connection"}) |> render_submit()
    page |> element("button[phx-value-ref='record:#{record["entity_id"]}']") |> render_click()
    page |> element("#atlas-edit") |> render_click()
    assert has_element?(page, "#record_source option[value='actor:moll'][selected]")
    assert has_element?(page, "#record_target option[value='zone:bridge'][selected]")
    page |> form("#atlas-form", record: %{name: "Still connected"}) |> render_submit()

    assert {:ok, %{record: %{source: "actor:moll", target: "zone:bridge"}}} =
             Atlas.get(ctx.owner, ctx.world.id, "record:" <> record["entity_id"])
  end

  test "public preview drops private records and editors; open windows save only drafts", ctx do
    {:ok, page, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/atlas")
    page |> element("#atlas-new") |> render_click()

    page
    |> form("#atlas-form", record: %{name: "GM secret", body: "Keep hidden"})
    |> render_submit()

    assert has_element?(page, "#atlas-records article", "GM secret")
    page |> element("#atlas-preview") |> render_click()
    refute has_element?(page, "#atlas-records article", "GM secret")
    refute has_element?(page, "#atlas-new")
    refute has_element?(page, "#atlas-form")
    _ctx = experience_fixture(ctx)
    {:ok, page, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/atlas")
    assert has_element?(page, "#atlas-window")
    page |> element("#atlas-new") |> render_click()
    assert has_element?(page, "#atlas-save", "Save draft")

    page
    |> form("#atlas-form", record: %{name: "Proposed future", body: "Not yet canon"})
    |> render_submit()

    refute has_element?(page, "#atlas-records article", "Proposed future")
    assert {:ok, %{count: 0}} = Atlas.search(ctx.owner, ctx.world.id, "Proposed future")
  end

  test "membership changes clear private results and an open editor on invalidation", ctx do
    builder = Scope.for_user(user_fixture())
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "builder", "builder")

    {:ok, record} =
      Atlas.save(
        ctx.owner,
        ctx.world.id,
        nil,
        0,
        %{"kind" => "article", "name" => "Hidden strategy", "body" => "Private editor text"},
        "strategy"
      )

    conn = log_in_user(build_conn(), builder.user)
    {:ok, page, _} = live(conn, ~p"/worlds/#{ctx.world.id}/atlas")
    page |> element("button[phx-value-ref='record:#{record["entity_id"]}']") |> render_click()
    page |> element("#atlas-edit") |> render_click()
    assert has_element?(page, "#atlas-form textarea", "Private editor text")
    page |> form("#atlas-search", search: %{query: String.duplicate("x", 101)}) |> render_submit()
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "viewer", "downgrade")
    send(page.pid, {:world_changed, ctx.world.id, 999})
    refute has_element?(page, "#atlas-records article", "Hidden strategy")
    refute has_element?(page, "#atlas-detail")
    refute has_element?(page, "#atlas-form")
    refute has_element?(page, "#atlas-new")
  end

  test "a delayed form cannot bind its old payload to the current editor", ctx do
    attrs = %{"kind" => "article", "name" => "Current record"}
    {:ok, record} = Atlas.save(ctx.owner, ctx.world.id, nil, 0, attrs, "current")
    {:ok, page, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/atlas")
    page |> element("button[phx-value-ref='record:#{record["entity_id"]}']") |> render_click()
    page |> element("#atlas-edit") |> render_click()

    render_submit(page, "save", %{
      "editor_request" => "old-editor-request",
      "record" => %{attrs | "name" => "Old form payload"}
    })

    assert {:ok, %{record: %{name: "Current record", revision: 1}}} =
             Atlas.get(ctx.owner, ctx.world.id, "record:" <> record["entity_id"])
  end
end
