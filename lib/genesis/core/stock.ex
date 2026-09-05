defmodule Genesis.Core.Stock do
  @moduledoc "Finite inventory lots. Splits retain depleted identities; every flow records its source lots."
  alias Genesis.Core.Item

  @spec balance(state :: map(), owner :: String.t(), commodity :: String.t()) :: non_neg_integer()
  def balance(state, owner, commodity),
    do:
      state.items
      |> Map.values()
      |> Enum.filter(&(&1.owner == {:actor, owner} and &1.commodity == commodity))
      |> Enum.map(& &1.quantity)
      |> Enum.sum()

  @spec flows(state :: map(), flows :: [map()], event_id :: String.t()) ::
          {:ok, map(), [map()]} | {:error, atom()}
  def flows(state, flows, event) do
    flows
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, state, []}, fn {flow, index}, {:ok, current, records} ->
      case flow(current, flow, event <> "/lot/" <> Integer.to_string(index)) do
        {:ok, next, record} -> {:cont, {:ok, next, records ++ [record]}}
        error -> {:halt, error}
      end
    end)
  end

  defp flow(
         state,
         %{"from" => from, "to" => to, "commodity" => commodity, "quantity" => quantity} = flow,
         id
       )
       when is_integer(quantity) and quantity in 1..1_000_000 do
    with true <- is_nil(from) or balance(state, from, commodity) >= quantity,
         true <- is_nil(to) or balance(state, to, commodity) + quantity <= 1_000_000,
         false <- Map.has_key?(state.items, id),
         {:ok, items, sources} <- debit(state.items, from, commodity, quantity) do
      items = credit(items, to, commodity, quantity, id, state.local_rules)
      {:ok, %{state | items: items}, Map.put(flow, "source_lots", sources)}
    else
      _ -> {:error, :insufficient_stock_or_capacity}
    end
  end

  defp flow(_state, _flow, _id), do: {:error, :invalid_quantity}

  defp debit(items, nil, _commodity, _quantity), do: {:ok, items, []}

  defp debit(items, owner, commodity, quantity) do
    {items, remaining, sources} =
      items
      |> Enum.sort()
      |> Enum.reduce({items, quantity, []}, fn
        {id, %{owner: {:actor, ^owner}, commodity: ^commodity, quantity: available} = item},
        {acc, remaining, sources}
        when remaining > 0 and available > 0 ->
          amount = min(available, remaining)

          {Map.put(acc, id, %{item | quantity: available - amount}), remaining - amount,
           sources ++ [%{"id" => id, "quantity" => amount}]}

        _, acc ->
          acc
      end)

    if remaining == 0, do: {:ok, items, sources}, else: {:error, :insufficient_stock}
  end

  defp credit(items, nil, _commodity, _quantity, _id, _rules), do: items

  defp credit(items, owner, commodity, quantity, id, rules),
    do:
      Map.put(
        items,
        id,
        struct(Item,
          id: id,
          name: rules["commodities"][commodity],
          commodity: commodity,
          quantity: quantity,
          owner: {:actor, owner},
          audience: {:actors, [owner]}
        )
      )
end
