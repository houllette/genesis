defmodule GenesisWeb.ReviewLiveTest do
  use GenesisWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Genesis.WorldFixtures
  alias Genesis.{Campaigns, Content, Repo, Travel, WorldNetwork}
  alias Genesis.Engine.{Runtime, Session, WorldSupervisor}
  alias Genesis.Persistence.{Experience, Publication}

  setup %{conn: conn} = tags do
    ctx = world_fixture(zero_duration: !tags[:positive], ruleset: "fantasy_local")

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
        %{generation: ctx.world.generation, revision: 0},
        %{
          "type" => "connection",
          "from" => "bridge",
          "to" => docks,
          "condition" => "open",
          "capacity" => 4,
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

    if tags[:positive] do
      {:ok, session} = Runtime.attach(ctx.owner, ctx.world.id, ctx.experience.id, "mara")
      {:ok, _} = Session.propose(session, "help", %{type: "help", target_id: "moll"})
      {:ok, _} = Session.confirm(session, "help", "help")
    else
      {:ok, quote} = Travel.preview(ctx.owner, ctx.world.id, ctx.experience.id, "mara", docks)

      {:ok, _} =
        Travel.move(ctx.owner, ctx.world.id, ctx.experience.id, "mara", quote.token, "travel")
    end

    {:ok, Map.merge(ctx, %{conn: log_in_user(conn, ctx.owner.user), docks: docks})}
  end

  test "review shows both sides of movement; sealing and canceling a preview do not publish",
       ctx do
    {:ok, workspace, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}")

    assert has_element?(workspace, "#experience-review")

    {:ok, page, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/review")

    assert has_element?(page, "#places-bridge", "Not present at this place")
    assert has_element?(page, "#places-#{ctx.docks}", "Mara")
    page |> element("#seal-review") |> render_click()
    assert Repo.get!(Experience, ctx.experience.id).status == "ready"
    refute has_element?(page, "#seal-review")
    page |> element("#preview-publication") |> render_click()
    assert has_element?(page, "#publication-preview", "2 places")
    refute Repo.get_by(Publication, world_id: ctx.world.id)
    page |> element("#cancel-publication") |> render_click()
    refute has_element?(page, "#publication-preview")
    assert Repo.get!(Experience, ctx.experience.id).status == "ready"
    page |> element("#preview-publication") |> render_click()
    page |> element("#confirm-publication") |> render_click()
    assert has_element?(page, "#publication-complete")
    assert Repo.get!(Experience, ctx.experience.id).status == "incorporated"
    assert Repo.get_by!(Publication, world_id: ctx.world.id).status == "installed"
  end

  @tag positive: true
  test "elapsed fiction has no misleading seal or publish shortcut", ctx do
    {:ok, page, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/review")

    assert has_element?(page, "#review-ineligible")
    refute has_element?(page, "#seal-review")
    refute has_element?(page, "#preview-publication")
    assert Repo.get!(Experience, ctx.experience.id).status == "active"
    assert has_element?(page, "#completion-form")

    page
    |> form("#scene-time-form",
      duration: %{value: "4", unit: "minute", reason: "A discussion at the bridge"}
    )
    |> render_submit()

    assert has_element?(page, "#recorded-elapsed", "300 seconds")
    assert has_element?(page, "#time-ledger", "+240s")

    page
    |> form("#completion-form",
      completion: %{
        elapsed_seconds: "7200",
        outcome: "abandoned",
        reason: "The crew withdrew after two hours"
      }
    )
    |> render_submit()

    assert has_element?(page, "#completion-summary", "7200 seconds")
    assert has_element?(page, "#completion-summary", "300 seconds")
    refute has_element?(page, "#completion-form")
    refute has_element?(page, "#preview-publication")
    assert Repo.get!(Experience, ctx.experience.id).status == "ready"
  end

  test "malformed time and completion payloads are rejected without losing the review", ctx do
    {:ok, page, _} =
      live(ctx.conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/review")

    for {event, payload} <- [
          {"elapse",
           %{
             "duration" => %{"value" => %{}, "unit" => "minute", "reason" => "Malformed"},
             "revision" => "1"
           }},
          {"elapse", %{"duration" => nil, "revision" => "1"}},
          {"finish", %{"completion" => %{"elapsed_seconds" => []}, "revision" => "1"}},
          {"finish", %{"completion" => nil, "revision" => "1"}},
          {"elapse", %{"duration" => %{"value" => "1"}, "revision" => nil}},
          {"finish", %{"completion" => %{"elapsed_seconds" => "1"}, "revision" => %{}}}
        ] do
      render_click(page, event, payload)
      assert has_element?(page, "#completion-form")
      assert Repo.get!(Experience, ctx.experience.id).status == "active"
    end
  end

  test "outsiders cannot render or forge a review command", ctx do
    outsider = Genesis.AccountsFixtures.user_fixture()
    conn = log_in_user(build_conn(), outsider)

    {:ok, page, _} =
      live(conn, ~p"/worlds/#{ctx.world.id}/experiences/#{ctx.experience.id}/review")

    refute has_element?(page, "#review-places")
    render_click(page, "preview", %{})
    refute has_element?(page, "#publication-preview")
    assert Repo.get!(Experience, ctx.experience.id).status == "active"
  end
end
