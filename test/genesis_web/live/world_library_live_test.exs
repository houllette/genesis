defmodule GenesisWeb.WorldLibraryLiveTest do
  use GenesisWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/worlds")
  end

  describe "world library" do
    setup :register_and_log_in_user

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
