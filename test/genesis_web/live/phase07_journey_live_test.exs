defmodule GenesisWeb.Phase07JourneyLiveTest do
  use GenesisWeb.ConnCase, async: false
  @moduletag :capture_log
  import Phoenix.LiveViewTest
  import Genesis.Phase07Fixtures
  alias Genesis.Content
  alias Genesis.Content.Atlas
  alias Genesis.Engine.WorldSupervisor
  alias Genesis.Persistence.History
  alias Genesis.WorldFixtures

  setup %{conn: conn} do
    ctx = prepared_world()

    start_supervised!(
      {WorldSupervisor,
       registry: Genesis.Engine.Registry,
       world_id: ctx.world.id,
       generation: 0,
       owner: self(),
       storage: :postgres}
    )

    {:ok, Map.put(ctx, :conn, log_in_user(conn, ctx.owner.user))}
  end

  test "native companion invitation, delivery, report and source navigation", ctx do
    ctx = WorldFixtures.experience_fixture(ctx)

    {:ok, page, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/resources")

    for type <- ["recruit", "agree"] do
      page
      |> form("#local-action-form", command: %{actor_id: "mara", type: type, target_id: "orin"})
      |> render_change()

      page |> form("#local-action-form") |> render_submit()
      assert has_element?(page, "#local-quote")
      page |> element("#confirm-local-action") |> render_click()
    end

    assert working(ctx, "bridge").actors["orin"].companion_of == "mara"

    {:ok, travel, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/travel")

    travel
    |> form("#travel-form",
      travel: %{
        actor: "mara",
        destination: "docks",
        exchange_type: "offer",
        target_id: "docks-representative",
        quantity: "1"
      }
    )
    |> render_submit()

    assert has_element?(travel, "#travel-party-size", "2")
    assert has_element?(travel, "#delivery-summary", "Offer 1")
    travel |> element("#confirm-travel") |> render_click()
    assert has_element?(travel, "#places-docks", "Orin")

    {:ok, history, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/history?#{%{experience_id: ctx.experience.id}}")

    {:ok, events} = History.page(ctx.owner, ctx.world.id, experience_id: ctx.experience.id)
    offer = Enum.find(events.events, &(&1.type == "offer"))
    history |> element("#recognize-#{offer.id}") |> render_click()
    assert has_element?(history, "#world-standings", "standing 1")

    {:ok, detail, _} =
      live(
        ctx.conn,
        ~p"/worlds/#{ctx.world.id}/history?#{%{event: offer.id, experience_id: ctx.experience.id}}"
      )

    assert has_element?(detail, "#history-detail", "offer")

    {:ok, review, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/review")

    assert has_element?(review, "#review-standings", "standing 1")
  end

  test "custom annotation editor preserves typed values and rejects invalid integers", ctx do
    {:ok, atlas, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/atlas")
    atlas |> element("#atlas-new") |> render_click()

    atlas
    |> form("#atlas-form",
      record: %{
        name: "Bridge notes",
        annotations: %{
          "0" => %{key: "span", type: "integer", value: "12"},
          "1" => %{key: "surveyed", type: "boolean", value: "true"}
        }
      }
    )
    |> render_submit()

    assert has_element?(atlas, "#atlas-records article", "Bridge notes")

    {:ok, %{records: [record]}} =
      Atlas.search(ctx.owner, ctx.world.id, "Bridge notes")

    assert record.fields == %{"note:span" => 12, "note:surveyed" => true}
    atlas |> element("button[phx-value-ref='#{record.id}']") |> render_click()
    atlas |> element("#atlas-edit") |> render_click()
    assert has_element?(atlas, "#annotation-value-0[value='12']")

    atlas
    |> form("#atlas-form",
      record: %{annotations: %{"0" => %{key: "span", type: "integer", value: "oops"}}}
    )
    |> render_submit()

    assert has_element?(atlas, "#atlas-form")

    assert {:ok, %{record: %{fields: %{"note:span" => 12}}}} =
             Atlas.get(ctx.owner, ctx.world.id, record.id)

    atlas
    |> form("#atlas-form")
    |> render_submit(%{"record" => %{"annotations" => %{"0" => "malformed"}}})

    assert has_element?(atlas, "#atlas-form")

    assert {:ok, %{record: %{fields: %{"note:span" => 12}}}} =
             Atlas.get(ctx.owner, ctx.world.id, record.id)
  end

  test "NPC editor saves explicit willingness separately from descriptive persona", ctx do
    {:ok, place, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/places/bridge")
    place |> element("#edit-actor-orin") |> render_click()

    place
    |> form("#record-form", record: %{follow_willing: "false", follow_trips: "3"})
    |> render_submit()

    assert {:ok, view} = Content.view(ctx.owner, ctx.world.id, "bridge")
    orin = Enum.find(view.actors, &(&1.id == "orin"))
    assert orin.companion_policy == %{"version" => 1, "willing" => false, "max_trips" => 3}
    assert orin.persona == ctx.seed.actors["orin"].persona
    assert orin.companion_of == nil
  end

  test "history rejects unauthenticated requests and unresolved source identities", ctx do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/worlds/#{ctx.world.id}/history")

    {:ok, page, _} = live(ctx.conn, ~p"/worlds/#{ctx.world.id}/history?source=not-an-event")
    assert has_element?(page, "#source-unavailable")
    refute has_element?(page, "#history-detail")
  end
end
