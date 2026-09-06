defmodule Genesis.Core.Economy do
  @moduledoc "Explicit production, supply-consuming recovery and merchant-authorized stock loss. No timers."
  alias Genesis.Core.Commerce

  @spec terms(state :: map(), actor :: String.t(), intent :: map()) ::
          {:ok, map()} | {:error, atom()}
  def terms(state, actor, %{type: "produce", target_id: recipe_id, quantity: quantity}) do
    r = state.local_rules["recipe"]

    cond do
      r["delay"] != 0 ->
        {:error, :timed_production_unavailable}

      recipe_id != r["id"] ->
        {:error, :unavailable}

      quantity > capacity(state) ->
        {:error, :production_capacity}

      true ->
        {:ok,
         %{
           "flows" => [
             Commerce.flow(actor, nil, r["input"], r["input_units"] * quantity),
             Commerce.flow(nil, actor, r["output"], r["output_units"] * quantity),
             Commerce.flow(nil, actor, r["waste"], r["waste_units"] * quantity)
           ],
           "summary" =>
             "Mill #{r["input_units"] * quantity} #{r["input"]} into #{r["output_units"] * quantity} #{r["output"]} and #{r["waste_units"] * quantity} #{r["waste"]}",
           "duration" => 0,
           "accounting_kind" => "recipe_conversion",
           "recipe" => r
         }}
    end
  end

  def terms(state, actor, %{type: "rest", target_id: actor}) do
    r = state.local_rules["rest"]
    current = Map.get(state.actors[actor].resources, r["resource"])

    if is_integer(current) and current < r["maximum"] do
      gain = min(r["gain"], r["maximum"] - current)

      {:ok,
       %{
         "flows" => [Commerce.flow(actor, nil, r["supply"], r["quantity"])],
         "summary" => "Consume #{r["quantity"]} #{r["supply"]}; recover #{gain} #{r["resource"]}",
         "duration" => r["duration"],
         "gain" => gain,
         "resource" => r["resource"],
         "accounting_kind" => "consumption"
       }}
    else
      {:error, :recovery_unavailable}
    end
  end

  def terms(state, actor, %{type: "disrupt", target_id: actor, quantity: quantity}) do
    if actor == state.settlement["merchant_id"] do
      input = state.local_rules["recipe"]["input"]

      {:ok,
       %{
         "flows" => [Commerce.flow(actor, nil, input, quantity)],
         "summary" => "Record #{quantity} #{input} lost from this merchant's supply",
         "duration" => 0,
         "accounting_kind" => "authorized_loss"
       }}
    else
      {:error, :unavailable}
    end
  end

  def terms(_state, _actor, _intent), do: {:error, :unavailable}

  defp capacity(state) do
    case (state.timeline || %{})["condition"] do
      "closed" -> 0
      "harsh" -> div(state.settlement["capacity"], 2)
      _ -> state.settlement["capacity"]
    end
  end

  @spec apply(state :: map(), actor :: String.t(), terms :: map()) :: map()
  def apply(state, actor, %{"gain" => gain, "resource" => resource}),
    do: update_in(state.actors[actor].resources[resource], &(&1 + gain))

  def apply(state, _actor, _terms), do: state
end
