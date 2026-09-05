defmodule Genesis.Core.Commerce do
  @moduledoc "Bounded finite-stock exchanges. Integer prices, no reservations and no side balance ledger."
  alias Genesis.Core.Stock

  @spec terms(state :: map(), actor :: String.t(), intent :: map()) ::
          {:ok, map()} | {:error, atom()}
  def terms(state, actor, %{type: type, target_id: merchant, quantity: quantity}) do
    market = state.settlement

    if merchant == market["merchant_id"] and merchant != actor do
      exchange(state, actor, merchant, type, quantity)
    else
      {:error, :unavailable}
    end
  end

  defp exchange(state, actor, merchant, type, quantity) when type in ["buy", "sell"] do
    if state.settlement["profile"]["exchange"] == "currency" do
      commodity = state.local_rules["recipe"]["input"]
      price = price(state, type)
      total = quantity * price
      {seller, buyer} = if type == "buy", do: {merchant, actor}, else: {actor, merchant}

      {:ok,
       %{
         "flows" => [
           flow(seller, buyer, commodity, quantity),
           flow(buyer, seller, state.local_rules["currency"], total)
         ],
         "unit_price" => price,
         "total" => total,
         "unit" => state.local_rules["currency"],
         "summary" => "#{type}: #{quantity} #{commodity} for #{total} minor units",
         "duration" => 0
       }}
    else
      {:error, :currency_disabled}
    end
  end

  defp exchange(state, actor, merchant, "barter", quantity) do
    b = state.local_rules["barter"]
    give = quantity * b["give_units"]
    receive = quantity * b["receive_units"]

    {:ok,
     %{
       "flows" => [
         flow(actor, merchant, b["give"], give),
         flow(merchant, actor, b["receive"], receive)
       ],
       "summary" => "Offer #{give} #{b["give"]} for #{receive} #{b["receive"]}",
       "duration" => 0
     }}
  end

  @spec price(state :: map(), side :: String.t()) :: pos_integer()
  def price(state, "buy") do
    market = state.settlement
    stock = Stock.balance(state, market["merchant_id"], state.local_rules["recipe"]["input"])
    multiplier = if stock <= market["scarcity_threshold"], do: market["multiplier"], else: 1
    market["price"] * multiplier
  end

  # Merchant bids round down and do not inflate at the scarcity boundary.
  def price(state, "sell"), do: div(state.settlement["price"], 2)

  @spec flow(
          from :: String.t() | nil,
          to :: String.t() | nil,
          commodity :: String.t(),
          quantity :: pos_integer()
        ) :: map()
  def flow(from, to, commodity, quantity),
    do: %{"from" => from, "to" => to, "commodity" => commodity, "quantity" => quantity}
end
