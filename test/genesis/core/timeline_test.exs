defmodule Genesis.Core.TimelineTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Curation, RecordedChange, Stock, Timeline, TimeSteps}
  alias Genesis.SettlementFixtures

  test "recorded actions and dated supply work interleave without rerolling, with resumable batches" do
    base = scheduled()
    {:ok, next, [effect]} = SettlementFixtures.action(base, "mara", "help", "moll", "help")

    record = %{
      "zone" => base.zone_id,
      "before" => base,
      "after" => next,
      "effect" => effect,
      "at" => effect.occurred_at,
      "cursor" => 1,
      "source_id" => "help-source"
    }

    {:ok, work} =
      Timeline.new(%{base.zone_id => base}, [record], base.time.value + 3 * 86_400, %{}, "window")

    assert {:ok, done} = Timeline.batch(work, 64)
    assert done["status"] == "ready"
    assert Stock.balance(done["states"][base.zone_id], "moll", "grain") == 6
    assert done["states"][base.zone_id].actors["mara"].resources["effort"] == 9
    assert {:ok, one} = Timeline.batch(work, 1)
    assert {:ok, chunked} = Timeline.batch(one, 64)
    assert chunked == done

    assert {:ok, published} =
             RecordedChange.publish(done["states"][base.zone_id], base, work["target"], %{})

    assert published.time.value == base.time.value + 259_200
    assert published.elapsed == 0
  end

  test "an earlier supply consequence cannot be overwritten by an incompatible recorded trade" do
    base = scheduled()
    later = %{base | time: %{base.time | value: base.time.value + 90_000}}

    {:ok, next, [effect]} =
      SettlementFixtures.action(later, "mara", "buy", "moll", "purchase", %{quantity: 1})

    record = %{
      "zone" => base.zone_id,
      "before" => later,
      "after" => next,
      "effect" => effect,
      "at" => effect.occurred_at,
      "cursor" => 1,
      "source_id" => "purchase-source"
    }

    {:ok, work} =
      Timeline.new(%{base.zone_id => base}, [record], base.time.value + 100_000, %{}, "window")

    assert {:ok, review} = Timeline.batch(work, 64)
    assert review["status"] == "needs_review"

    assert [%{"source_id" => "purchase-source", "reason" => "recorded_dependency_changed"}] =
             review["conflicts"]

    assert Stock.balance(review["states"][base.zone_id], "moll", "grain") == 10
  end

  test "two locally recorded occurrences at one point deduplicate without a false conflict" do
    base = scheduled()

    {:ok, base} =
      Curation.apply(base, "second", %{
        "kind" => "schedule",
        "name" => "Second mill",
        "version" => 1,
        "first_at" => base.time.value + 86_400,
        "actor_id" => "moll",
        "action" => "produce",
        "target_id" => "mill",
        "quantity" => 1
      })

    {:ok, _, _, steps} = TimeSteps.prepare(base, base.time.value + 86_400, %{}, %{})

    records =
      Enum.with_index(steps, fn step, cursor ->
        %{
          "zone" => base.zone_id,
          "before" => step.before,
          "after" => step.next,
          "effect" => step.event,
          "at" => step.event.occurred_at,
          "cursor" => cursor,
          "source_id" => "source-#{cursor}"
        }
      end)

    {:ok, work} =
      Timeline.new(%{base.zone_id => base}, records, base.time.value + 86_400, %{}, "window")

    assert {:ok, done} = Timeline.batch(work, 64)
    assert done["status"] == "ready"
    assert length(done["generated"]) == 2
    assert Stock.balance(done["states"][base.zone_id], "moll", "ration") == 2
  end

  test "a cross-zone condition contradicting local due work requires review, not an invented merge" do
    base = scheduled()

    attrs =
      base.timeline["schedules"]["mill"]
      |> Map.put("kind", "schedule")
      |> Map.put("version", 2)
      |> Map.put("dependency", %{"zone_id" => "hill", "condition" => "normal"})

    {:ok, base} = Curation.apply(base, "mill", attrs)

    hill = %{
      SettlementFixtures.scene()
      | zone_id: "hill",
        items: %{},
        actors: %{},
        knowledge: %{},
        settlement: nil
    }

    {:ok, hill} =
      Curation.apply(hill, "flood", %{
        "kind" => "schedule",
        "name" => "Flood upstream",
        "version" => 1,
        "first_at" => base.time.value + 100,
        "action" => "condition",
        "condition" => "closed"
      })

    {:ok, _, _, [step]} =
      TimeSteps.prepare(base, base.time.value + 86_400, %{}, %{
        "hill" => %{"condition" => "normal"}
      })

    record = %{
      "zone" => base.zone_id,
      "before" => step.before,
      "after" => step.next,
      "effect" => step.event,
      "at" => step.event.occurred_at,
      "cursor" => 1,
      "source_id" => "milling-source"
    }

    {:ok, work} =
      Timeline.new(
        %{base.zone_id => base, "hill" => hill},
        [record],
        base.time.value + 86_400,
        %{},
        "window"
      )

    assert {:ok, result} = Timeline.batch(work, 64)
    assert result["status"] == "needs_review"

    assert [%{"source_id" => "milling-source", "reason" => "local_due_conflict"}] =
             result["conflicts"]

    assert result["states"]["hill"].timeline["condition"] == "closed"
    assert Stock.balance(result["states"][base.zone_id], "moll", "ration") == 0
  end

  defp scheduled do
    state = SettlementFixtures.scene()

    {:ok, state} =
      Curation.apply(state, "mill", %{
        "kind" => "schedule",
        "name" => "Daily milling",
        "version" => 1,
        "first_at" => state.time.value + 86_400,
        "every" => %{"unit" => "day", "value" => 1},
        "actor_id" => "moll",
        "action" => "produce",
        "target_id" => "mill",
        "quantity" => 1
      })

    state
  end
end
