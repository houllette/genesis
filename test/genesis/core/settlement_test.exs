defmodule Genesis.Core.SettlementTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Context, Curation, Scene, State, Stock}
  alias Genesis.SettlementFixtures, as: Fixtures
  import Genesis.SceneFixtures

  test "legacy rules do not pretend to enable settlement accounting" do
    attrs = %{"kind" => "settlement", "name" => "Ashfall market"}
    assert {:error, :unsupported_capability} = Curation.apply(scene(), "market", attrs)
  end

  test "the connected journey conserves trade, declares recipe waste and consumes supplies" do
    initial = Fixtures.scene()

    assert {:ok, quote} =
             Scene.propose(
               initial,
               "mara",
               %{type: "buy", target_id: "moll", quantity: 2},
               "quote"
             )

    assert quote.terms["total"] == 20

    assert {:ok, disrupted, [loss]} =
             Fixtures.action(initial, "moll", "disrupt", "moll", "supply-loss", %{quantity: 8})

    assert loss.accounting["flows"] |> hd() |> Map.fetch!("quantity") == 8

    assert {:error, :stale_proposal} =
             Scene.confirm(disrupted, quote, inputs(disrupted, "changed-price"))

    assert {:ok, quote} =
             Scene.propose(
               disrupted,
               "mara",
               %{type: "buy", target_id: "moll", quantity: 2},
               "new-quote"
             )

    assert quote.terms["total"] == 40

    assert {:ok, bought, [receipt]} =
             Scene.confirm(disrupted, quote, inputs(disrupted, "purchase"))

    assert Stock.balance(bought, "mara", "coin") == 60
    assert Stock.balance(bought, "moll", "coin") == 240
    assert Stock.balance(bought, "mara", "grain") == 4
    assert Stock.balance(bought, "moll", "grain") == 2
    assert Enum.map(receipt.accounting["flows"], & &1["quantity"]) == [2, 40]

    assert {:ok, milled, [production]} =
             Fixtures.action(bought, "mara", "produce", "mill", "mill", %{quantity: 2})

    assert Stock.balance(milled, "mara", "grain") == 0
    assert Stock.balance(milled, "mara", "ration") == 5
    assert Stock.balance(milled, "mara", "chaff") == 2
    assert Enum.map(production.accounting["flows"], & &1["quantity"]) == [4, 2, 2]
    assert milled.items["mara-grain"].quantity == 0

    assert {:error, :recovery_unavailable} =
             Fixtures.action(milled, "mara", "rest", "mara", "full")

    tired = put_in(milled.actors["mara"].resources["effort"], 7)
    assert {:ok, rested, [_]} = Fixtures.action(tired, "mara", "rest", "mara", "rest")
    assert Stock.balance(rested, "mara", "ration") == 4
    assert rested.actors["mara"].resources["effort"] == 9
    assert rested.elapsed == 3600
    assert {:ok, ^rested} = State.restore(rested)
  end

  test "quotes use fictional expiry and survive lifecycle-only pause and resume" do
    state = Fixtures.scene()

    assert {:ok, quote} =
             Scene.propose(state, "mara", %{type: "buy", target_id: "moll", quantity: 1}, "quote")

    paused = State.pause(state)
    assert {:error, :stale_proposal} = Scene.confirm(paused, quote, inputs(paused, "paused"))
    resumed = State.resume(paused)
    assert {:ok, _, [_]} = Scene.confirm(resumed, quote, inputs(resumed, "resumed"))
    expired = %{state | time: %{state.time | value: quote.terms["expires_at"]}}
    assert {:error, :quote_expired} = Scene.confirm(expired, quote, inputs(expired, "late"))
    refute Map.has_key?(Scene.proposal_view(quote).terms, "basis")
  end

  test "affiliation is voluntary and private; offerings fulfill one obligation and aid consumes real stock" do
    for profile <- ["temple_market", "mutual_aid"] do
      state = Fixtures.scene(profile: profile)

      assert {:error, :aid_unavailable} =
               Fixtures.action(state, "mara", "aid", "reed", "premature")

      assert {:ok, member, [_]} = Fixtures.action(state, "mara", "affiliate", "reed", "join")
      assert {:ok, stranger} = State.view(member, %{role: :player, actor_id: "courier"})
      refute Enum.any?(stranger.knowledge, &String.starts_with?(&1.predicate, "local:"))
      refute Context.institution(member, "mara", "reed").eligible

      assert {:ok, offered, [_]} =
               Fixtures.action(member, "mara", "offer", "reed", "offering", %{quantity: 1})

      assert Stock.balance(offered, "reed", "ration") == 1
      assert Stock.balance(offered, "mara", "ration") == 2
      assert Context.institution(offered, "mara", "reed").eligible
      refute Context.institution(offered, "mara", "moll").eligible
      assert {:ok, aided, [_]} = Fixtures.action(offered, "mara", "aid", "reed", "aid")
      assert Stock.balance(aided, "reed", "grain") == 3
      assert Stock.balance(aided, "mara", "grain") == 3
      assert {:error, :aid_unavailable} = Fixtures.action(aided, "mara", "aid", "reed", "repeat")

      refute Enum.any?(aided.knowledge, fn {_id, k} ->
               k.kind == :fact and String.contains?(k.predicate, "deity")
             end)
    end
  end

  test "barter is explicit, sell rounds down and disabling cannot orphan holdings" do
    barter = Fixtures.scene(profile: "mutual_aid")

    assert {:error, :currency_disabled} =
             Fixtures.action(barter, "mara", "buy", "moll", "buy", %{quantity: 1})

    assert {:ok, traded, [_]} =
             Fixtures.action(barter, "mara", "barter", "moll", "barter", %{quantity: 2})

    assert Stock.balance(traded, "mara", "ration") == 1
    assert Stock.balance(traded, "mara", "grain") == 6
    assert Stock.balance(traded, "moll", "ration") == 2
    money = Fixtures.scene()
    money = put_in(money.settlement["price"], 11)

    assert {:ok, sold, [_]} =
             Fixtures.action(money, "mara", "sell", "moll", "sell", %{quantity: 1})

    assert Stock.balance(sold, "mara", "coin") == 105

    assert {:error, :migration_required} =
             Curation.apply(
               money,
               "settlement",
               Map.put(Fixtures.configuration(), "enabled", false)
             )

    assert {:error, :migration_required} =
             Curation.apply(money, "settlement", Fixtures.configuration(profile: "mutual_aid"))
  end

  test "unknown violations are not omniscient reputation; only the institution can adjudicate a known report" do
    state = Fixtures.scene(witnessing: false)

    assert {:ok, violated, [event]} =
             Fixtures.action(state, "mara", "trespass", "reed", "trespass")

    assert event.audience == {:actors, ["mara"]}

    assert {:error, :adjudication_unavailable} =
             Fixtures.action(violated, "reed", "adjudicate", "mara", "unknown")

    assert {:error, :unavailable} =
             Fixtures.action(violated, "courier", "report", "reed", "forged", %{
               record_id: "trespass/violation"
             })

    assert {:ok, reported, [_]} =
             Fixtures.action(violated, "mara", "report", "reed", "report", %{
               record_id: "trespass/violation"
             })

    assert {:error, :adjudication_unavailable} =
             Fixtures.action(reported, "moll", "adjudicate", "mara", "not-authority")

    assert {:ok, judged, [_]} =
             Fixtures.action(reported, "reed", "adjudicate", "mara", "judgment")

    assert judged.knowledge["judgment/restitution"].value == "pending"
    assert judged.knowledge["judgment/standing"].value == "restricted"
    assert {:ok, outsider} = State.view(judged, %{role: :player, actor_id: "courier"})
    refute Enum.any?(outsider.knowledge, &String.starts_with?(&1.predicate, "local:"))
  end

  test "invalid quantities, unavailable stock, delayed production, refusal and client authority fields consume nothing" do
    state = Fixtures.scene()

    for quantity <- [-1, 0, 1.5, "2", 101, 9_000_000_000] do
      assert {:error, :invalid_request} =
               Fixtures.action(state, "mara", "buy", "moll", "bad", %{quantity: quantity})
    end

    assert {:error, :insufficient_stock_or_capacity} =
             Fixtures.action(state, "mara", "buy", "moll", "too-many", %{quantity: 13})

    assert {:error, :production_capacity} =
             Fixtures.action(state, "mara", "produce", "mill", "capacity", %{quantity: 11})

    assert {:error, :unavailable} =
             Fixtures.action(state, "mara", "disrupt", "moll", "steal", %{quantity: 1})

    assert {:error, :invalid_request} =
             Fixtures.action(state, "mara", "buy", "moll", "forged", %{quantity: 1, role: :gm})

    assert {:error, :institution_refused} =
             Fixtures.action(
               put_in(state.settlement["accepting_members"], false),
               "mara",
               "affiliate",
               "reed",
               "refused"
             )

    assert {:error, :timed_production_unavailable} =
             Fixtures.action(
               put_in(state.local_rules["recipe"]["delay"], 60),
               "mara",
               "produce",
               "mill",
               "delay",
               %{quantity: 1}
             )

    assert Stock.balance(state, "mara", "coin") == 100
    assert state.elapsed == 0
  end

  test "bounded trade combinations conserve both sides and rejected requests cannot mint currency" do
    for price <- 2..13, quantity <- 1..6 do
      initial = put_in(Fixtures.scene().settlement["price"], price)

      assert {:ok, bought, [_]} =
               Fixtures.action(initial, "mara", "buy", "moll", "purchase", %{quantity: quantity})

      assert Stock.balance(bought, "mara", "coin") + Stock.balance(bought, "moll", "coin") == 300
      assert Stock.balance(bought, "mara", "grain") + Stock.balance(bought, "moll", "grain") == 14

      assert {:ok, sold, [_]} =
               Fixtures.action(bought, "mara", "sell", "moll", "resale", %{quantity: quantity})

      assert Stock.balance(sold, "mara", "coin") == 100 - quantity * (price - div(price, 2))
      assert Stock.balance(sold, "moll", "grain") == 12
    end

    state = Fixtures.scene()

    {:ok, quote} =
      Scene.propose(state, "mara", %{type: "buy", target_id: "moll", quantity: 1}, "quote")

    irrelevant = %{state | description: "A different painted sign", revision: state.revision + 1}
    assert :ok = Scene.revalidate(irrelevant, quote)

    assert {:error, :invalid_request} =
             Fixtures.action(state, "mara", "produce", "mill", "mint", %{
               quantity: 1,
               commodity: "coin"
             })
  end

  test "beliefs and donations cannot forge affiliation and irrelevant context cannot earn aid" do
    state = Fixtures.scene()

    rumor = %{
      state.knowledge["rumor"]
      | predicate: "local:member",
        object_id: "reed",
        audience: {:actors, ["mara", "reed"]}
    }

    claim = %{rumor | id: "claimed-offering", predicate: "local:offering", value: "fulfilled"}

    state = %{
      state
      | knowledge: state.knowledge |> Map.put(rumor.id, rumor) |> Map.put(claim.id, claim)
    }

    refute Context.institution(state, "mara", "reed").eligible

    assert {:ok, donated, [_]} =
             Fixtures.action(state, "mara", "offer", "reed", "voluntary", %{quantity: 1})

    assert Stock.balance(donated, "reed", "ration") == 1
    refute Context.institution(donated, "mara", "reed").eligible

    assert {:error, :aid_unavailable} =
             Fixtures.action(donated, "mara", "aid", "reed", "no-membership")

    assert {:ok, witnessed, [_]} = Fixtures.action(state, "mara", "trespass", "reed", "seen")

    assert {:ok, judged, [event]} =
             Fixtures.action(witnessed, "reed", "adjudicate", "mara", "lawful")

    assert event.source_ids == ["seen/observation"]
    assert judged.knowledge["lawful/restitution"].audience == {:actors, ["mara", "reed"]}
  end

  test "restored state rejects mismatched denominations, aggregate overflows and orphaned representatives" do
    state = Fixtures.scene()
    fake = %{state.items["mara-coin"] | id: "fake-lot", quantity: 1_000_000}

    assert {:error, :invalid_state} =
             State.restore(%{state | items: Map.put(state.items, fake.id, fake)})

    assert {:error, :invalid_state} =
             State.restore(put_in(state.items["mara-coin"].name, "Disguised tokens"))

    assert {:error, :invalid_state} =
             State.restore(put_in(state.settlement["representative_id"], "missing"))

    assert {:error, :migration_required} =
             Curation.apply(
               state,
               "settlement",
               Map.merge(Fixtures.configuration(), %{
                 "merchant_id" => "reed",
                 "representative_id" => "moll"
               })
             )

    assert {:error, :use_stock_controls} =
             Curation.apply(state, "mara-coin", %{
               "kind" => "item",
               "name" => "Minted",
               "quantity" => 1000
             })
  end
end
