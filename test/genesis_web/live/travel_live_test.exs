defmodule GenesisWeb.TravelLiveTest do
  use GenesisWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Genesis.WorldFixtures
  alias Genesis.{Campaigns, Content, WorldNetwork}
  alias Genesis.Engine.WorldSupervisor

  setup %{conn: conn} do
    ctx = world_fixture(zero_duration: true, ruleset: "fantasy_local")

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

    {:ok, _} =
      WorldNetwork.save(
        ctx.owner,
        ctx.world.id,
        %{generation: 0, revision: 0},
        %{
          "type" => "connection",
          "from" => "bridge",
          "to" => docks,
          "condition" => "open",
          "capacity" => 1,
          "visibility" => "public"
        },
        "link"
      )

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara",
        "bind"
      )

    ctx = experience_fixture(ctx)
    {:ok, Map.merge(ctx, %{conn: log_in_user(conn, ctx.owner.user), docks: docks})}
  end

  test "GM previews, cancels, confirms, and inspects the new working destination", ctx do
    {:ok, workspace, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}")

    assert has_element?(workspace, "#experience-travel")

    {:ok, page, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/travel")

    assert has_element?(page, "#travel-boundary", "Review all visited places together")
    refute has_element?(page, "#travel-preview")

    page
    |> form("#travel-form", travel: %{actor: "mara", destination: ctx.docks})
    |> render_submit()

    assert has_element?(page, "#travel-preview", "Docks")
    page |> element("#cancel-travel") |> render_click()
    refute has_element?(page, "#travel-preview")

    page
    |> form("#travel-form", travel: %{actor: "mara", destination: ctx.docks})
    |> render_submit()

    page |> element("#confirm-travel") |> render_click()
    refute has_element?(page, "#travel-preview")
    assert has_element?(page, "#travel-places article", "Docks")
    assert has_element?(page, "#places-#{ctx.docks}", "Mara")
    refute has_element?(page, "#places-bridge", "Mara")

    {:ok, resources, _} =
      live(
        ctx.conn,
        ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/resources?zone=#{ctx.docks}"
      )

    assert has_element?(resources, "#resource-scope", "Docks")
    assert has_element?(resources, "#resource-travel")
  end

  test "forged unbound participants cannot produce a confirmation", ctx do
    {:ok, page, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/travel")

    render_submit(page, "preview", %{
      "travel" => %{"actor" => "courier", "destination" => ctx.docks}
    })

    refute has_element?(page, "#travel-preview")
    assert has_element?(page, "#travel-places article", "Mara")
  end

  test "unauthenticated visitors cannot enter travel", ctx do
    path = ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/travel"
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), path)
  end
end
