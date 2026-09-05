defmodule GenesisWeb.WorldLibraryLiveTest do
  use GenesisWeb.ConnCase, async: false
  alias Genesis.Accounts.Scope
  alias Genesis.Campaigns
  alias Genesis.Content
  alias Genesis.Engine.WorldSupervisor
  alias Genesis.Experiences
  alias Genesis.Workspace
  alias Genesis.Worlds
  import Phoenix.LiveViewTest

  test "requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/worlds")
  end

  describe "world library" do
    setup :register_and_log_in_user

    test "pins a non-Gregorian epoch through native creation, then records a calendar-relative scene",
         %{conn: conn, user: user} do
      {:ok, page, _} = live(conn, ~p"/worlds")

      {:ok, workspace, _} =
        page
        |> form("#new-world-form",
          world: %{
            name: "Thirteen months",
            ruleset: "fantasy_demo",
            calendar_kind: "coptic",
            epoch_year: "1742",
            epoch_month: "12",
            epoch_day: "30"
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(workspace, "#world-title", "Thirteen months")
      scope = Scope.for_user(user)
      [world] = Worlds.list_worlds(scope)

      start_supervised!(
        {WorldSupervisor,
         registry: Genesis.Engine.Registry,
         world_id: world.id,
         generation: world.generation,
         owner: self(),
         storage: :postgres}
      )

      assert world.calendar["implementation"] == "coptic"
      assert world.calendar["epoch"] == %{"year" => 1742, "month" => 12, "day" => 30}

      {:ok, %{"zone_id" => zone}} =
        Content.create_zone(scope, world.id, %{"name" => "River"}, "place")

      {:ok, campaign} = Campaigns.create_campaign(scope, world.id, %{"name" => "Crew"}, "crew")

      {:ok, exp} =
        Experiences.create(
          scope,
          world.id,
          campaign.id,
          %{"name" => "A month", "zone_id" => zone},
          "exp"
        )

      {:ok, _} = Experiences.start(scope, world.id, exp.id, 0)
      {:ok, review, _} = live(conn, ~p"/worlds/#{world.id}/experiences/#{exp.id}/review")

      review
      |> form("#scene-time-form",
        duration: %{value: "1", unit: "month", reason: "Until the end of the short month"}
      )
      |> render_submit()

      assert has_element?(review, "#recorded-elapsed", "432000 seconds")
      assert {:ok, persisted} = Workspace.experience_view(scope, world.id, exp.id)
      assert persisted.elapsed == 432_000
      assert {:ok, unchanged} = Worlds.get_world(scope, world.id)
      assert unchanged.fictional_time == 0
    end

    test "creates a world from a native form and reopens its committed workspace", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/worlds")
      assert has_element?(view, "#new-world-form")

      {:ok, workspace, _} =
        view
        |> form("#new-world-form",
          world: %{name: "Ashfall", ruleset: "fantasy_demo", profile: "village"}
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(workspace, "#world-title", "Ashfall")
      assert has_element?(workspace, "#new-zone-form")
      {:ok, library, _} = live(conn, ~p"/worlds")
      assert has_element?(library, "#worlds article", "Ashfall")
    end
  end
end
