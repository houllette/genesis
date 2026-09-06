defmodule GenesisWeb.TimeLiveTest do
  use GenesisWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Genesis.WorldFixtures
  alias Genesis.Engine.{Runtime, WorldSupervisor}

  alias Genesis.Persistence.{
    Experience,
    Preparation,
    PrepareTimeline,
    Seals,
    Snapshot,
    Snapshots,
    World
  }

  alias Genesis.Repo

  test "native review makes an explicit decision, prepares, inspects and publishes once", %{
    conn: conn
  } do
    ctx = world_fixture() |> experience_fixture()

    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: 0,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres}
    )

    {:ok, basis} = Seals.basis(ctx.experience)

    {:ok, _} =
      Runtime.call(
        ctx.owner,
        ctx.world.id,
        {:status, ctx.experience.id,
         {:finish,
          %{
            "elapsed_seconds" => 7200,
            "outcome" => "completed",
            "reason" => "Delivered",
            "basis" => basis
          }}, 0, "finish"}
      )

    {:ok, view, _} = live(log_in_user(conn, ctx.owner.user), ~p"/worlds/#{ctx.world.id}/time")
    assert has_element?(view, "#published-time", "0 seconds")

    view
    |> form("#time-decision-form",
      decision: %{
        experience_id: ctx.experience.id,
        mode: "include",
        elapsed_seconds: "7200",
        reason: "Reviewed the courier"
      }
    )
    |> render_submit()

    assert has_element?(view, "#window-experiences", "Decision: include")

    view
    |> form("#prepare-time-form", plan: %{downtime_seconds: "0", reason: "Publish the courier"})
    |> render_submit()

    assert has_element?(view, "#time-candidate", "preparing")
    refute has_element?(view, "#publish-time")
    row = Repo.get_by!(Preparation, world_id: ctx.world.id)

    assert :ok =
             PrepareTimeline.perform(%Oban.Job{
               args: %{"preparation_id" => row.id, "world_id" => ctx.world.id, "generation" => 0}
             })

    view |> element("#refresh-time") |> render_click()
    assert has_element?(view, "#candidate-target", "7200s")
    assert has_element?(view, "#time-impacts")
    view |> element("#preview-time") |> render_click()
    assert has_element?(view, "#time-confirmation", "7200s")
    view |> element("#publish-time") |> render_click()
    assert has_element?(view, "#published-time", "7200 seconds")
    assert Repo.get!(Experience, ctx.experience.id).status == "incorporated"
    assert Repo.get!(World, ctx.world.id).fictional_time == 7200
  end

  test "a different signed-in user cannot inspect the window", %{conn: conn} do
    ctx = world_fixture() |> experience_fixture()
    outsider = Genesis.AccountsFixtures.user_fixture()
    {:ok, view, _} = live(log_in_user(conn, outsider), ~p"/worlds/#{ctx.world.id}/time")
    assert has_element?(view, "#time-unavailable")
    refute has_element?(view, "#time-review")
    render_click(view, "prepare", %{"plan" => nil})
    refute Repo.get_by(Preparation, world_id: ctx.world.id)
  end

  test "native schedule creation stores a typed future routine without advancing time", %{
    conn: conn
  } do
    ctx = world_fixture(ruleset: "fantasy_local")

    start_supervised!(
      {WorldSupervisor,
       world_id: ctx.world.id,
       generation: 0,
       registry: Genesis.Engine.Registry,
       owner: self(),
       storage: :postgres}
    )

    {:ok, view, _} = live(log_in_user(conn, ctx.owner.user), ~p"/worlds/#{ctx.world.id}/time")

    view
    |> form("#schedule-form-bridge",
      schedule: %{
        name: "Morning milling",
        action: "produce",
        actor_id: "moll",
        target_id: "mill",
        quantity: "1",
        first_at: "60",
        every_value: "1",
        every_unit: "day"
      }
    )
    |> render_submit()

    assert has_element?(view, "#schedule-places", "Morning milling")
    assert Repo.get!(World, ctx.world.id).fictional_time == 0

    assert {:ok, state} =
             Snapshots.load(Repo.get!(Snapshot, ctx.published.id))

    assert map_size(state.timeline["schedules"]) == 1
  end
end
