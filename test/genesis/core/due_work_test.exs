defmodule Genesis.Core.DueWorkTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Curation, DueWork, Stock}
  alias Genesis.SettlementFixtures
  alias Genesis.Time.Calendar

  test "dated production uses real inputs once and bounded chunks equal one pass" do
    base = SettlementFixtures.scene()
    start = base.time.value
    attrs = schedule(start + 60)
    assert {:ok, state} = Curation.apply(base, "mill", attrs)
    assert {:ok, whole, events, :done} = DueWork.advance(state, start + 180, %{}, 16)
    assert Stock.balance(whole, "moll", "grain") == 6
    assert Stock.balance(whole, "moll", "ration") == 3
    assert Enum.map(events, & &1.occurred_at) == [start + 60, start + 120, start + 180]
    assert {:ok, first, [event], :more} = DueWork.advance(state, start + 180, %{}, 1)
    assert event.id == hd(events).id
    assert {:ok, rest, tail, :done} = DueWork.advance(first, start + 180, %{}, 16)
    assert rest == whole
    assert [event | tail] == events
    assert {:ok, ^whole, [], :done} = DueWork.advance(whole, start + 180, %{}, 16)
  end

  test "exhausted inputs record a refusal without creating supplies or retrying the occurrence" do
    base = SettlementFixtures.scene(merchant_stock: 2)
    assert {:ok, state} = Curation.apply(base, "mill", schedule(base.time.value + 60))

    assert {:ok, next, [_, refused], :done} =
             DueWork.advance(state, base.time.value + 120, %{}, 8)

    assert Stock.balance(next, "moll", "ration") == 1
    assert refused.result["status"] == "skipped"
    assert {:ok, ^next, [], :done} = DueWork.advance(next, next.time.value, %{}, 8)
  end

  test "no target, backward targets, malformed schedules and implicit PC routines reject" do
    base = SettlementFixtures.scene()
    assert {:error, :invalid_target} = DueWork.advance(base, nil, %{}, 8)
    assert {:error, :invalid_target} = DueWork.advance(base, base.time.value - 1, %{}, 8)
    assert {:error, _} = Curation.apply(base, "mill", schedule(base.time.value))

    assert {:error, _} =
             Curation.apply(
               base,
               "mill",
               Map.put(schedule(base.time.value + 1), "actor_id", "mara")
             )

    assert {:error, _} =
             Curation.apply(base, "mill", Map.put(schedule(base.time.value + 1), "code", "eval"))
  end

  test "calendar-relative recurrence and half-open availability preserve Coptic rollover across chunks" do
    base = SettlementFixtures.scene()
    base = %{base | time: %{base.time | value: 0, calendar_id: "village"}}

    frame = %{
      "format" => 1,
      "id" => "village",
      "version" => 1,
      "implementation" => "coptic",
      "epoch" => %{"year" => 1742, "month" => 12, "day" => 30}
    }

    attrs =
      schedule(1)
      |> Map.put("every", %{"unit" => "month", "value" => 1})
      |> Map.put("availability", %{"from" => 1, "to" => 5 * 86_400 + 1})

    {:ok, state} = Curation.apply(base, "mill", attrs)

    assert {:ok, whole, [first, boundary], :done} =
             DueWork.advance(state, 5 * 86_400 + 1, frame, 16)

    assert first.result["status"] == "applied"
    assert boundary.occurred_at == 5 * 86_400 + 1
    assert boundary.result["status"] == "skipped"
    assert Stock.balance(whole, "moll", "ration") == 1
    assert {:ok, part, [^first], :more} = DueWork.advance(state, 5 * 86_400 + 1, frame, 1)
    assert {:ok, ^whole, [^boundary], :done} = DueWork.advance(part, 5 * 86_400 + 1, frame, 16)

    assert Calendar.contains?(
             %{base.time | value: 5 * 86_400 + 1},
             5 * 86_400 + 1,
             6 * 86_400,
             frame
           )
  end

  test "dated closed conditions stop production and dependent effects retain causes with a depth cap" do
    base = SettlementFixtures.scene()

    {:ok, base} =
      Curation.apply(base, "closure", %{
        "kind" => "schedule",
        "name" => "Winter closure",
        "version" => 1,
        "first_at" => base.time.value + 30,
        "action" => "condition",
        "condition" => "closed"
      })

    {:ok, base} = Curation.apply(base, "mill", schedule(base.time.value + 60))

    assert {:ok, next, [condition, skipped], :done} =
             DueWork.advance(base, base.time.value + 60, %{}, 16)

    assert next.timeline["condition"] == "closed"
    assert skipped.result["reason"] == "production_capacity"
    assert Stock.balance(next, "moll", "grain") == 12
    other = %{SettlementFixtures.scene() | zone_id: "hill"}
    other = put_in(other.settlement["site_id"], "hill")

    other = %{
      other
      | items: Map.reject(other.items, fn {_, item} -> match?({:zone, _}, item.owner) end)
    }

    attrs =
      schedule(other.time.value + 60)
      |> Map.put("dependency", %{"zone_id" => base.zone_id, "condition" => "closed"})

    {:ok, other} = Curation.apply(other, "mill", attrs)
    context = %{base.zone_id => DueWork.context_value(next)}

    assert {:ok, _, [effect], :done} =
             DueWork.advance(other, other.time.value + 60, %{}, 16, context)

    assert effect.causal_parent_ids == [condition.id]
    assert effect.causal_root_id == condition.id
    assert effect.causal_depth == 1
    bad = put_in(context[base.zone_id]["source"][:causal_depth], 8)

    assert {:error, :invalid_occurrence} =
             DueWork.advance(other, other.time.value + 60, %{}, 16, bad)

    assert {:error, _} =
             Curation.apply(other, "spawn", Map.put(attrs, "spawn_schedules", [attrs]))
  end

  defp schedule(at),
    do: %{
      "kind" => "schedule",
      "name" => "Mill grain",
      "version" => 1,
      "first_at" => at,
      "every" => %{"unit" => "minute", "value" => 1},
      "actor_id" => "moll",
      "action" => "produce",
      "target_id" => "mill",
      "quantity" => 1
    }
end
