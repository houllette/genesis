defmodule Genesis.Core.Settlement do
  @moduledoc "One locally owned market and institution; their stores are existing actors' inventory, never parallel balances."
  alias Genesis.Core.{Audience, Item, Scope, Stock}
  alias Genesis.Systems.{LocalRules, WorldProfile}

  @fields ~w(kind name profile merchant_id representative_id tradition claim price scarcity_threshold multiplier capacity quote_ttl accepting_members witnessing enabled)

  @spec configure(state :: map(), id :: String.t(), attrs :: map()) ::
          {:ok, map()} | {:error, atom()}
  def configure(%{local_rules: nil}, _id, _attrs), do: {:error, :unsupported_capability}

  def configure(state, id, attrs) do
    with true <- Map.keys(attrs) -- @fields == [],
         {:ok, profile} <- WorldProfile.preset(attrs["profile"]),
         :ok <- migration(state, profile, Map.get(attrs, "enabled", true), attrs),
         true <- is_nil(state.settlement) or state.settlement["id"] == id do
      record = %{
        "id" => id,
        "version" => 1,
        "name" => attrs["name"],
        "profile" => profile,
        "merchant_id" => attrs["merchant_id"],
        "representative_id" => attrs["representative_id"],
        "site_id" => state.zone_id,
        "tradition" => attrs["tradition"],
        "claim" => Map.get(attrs, "claim", ""),
        "price" => Map.get(attrs, "price", 10),
        "scarcity_threshold" => Map.get(attrs, "scarcity_threshold", 5),
        "multiplier" => Map.get(attrs, "multiplier", 2),
        "capacity" => Map.get(attrs, "capacity", 10),
        "quote_ttl" => Map.get(attrs, "quote_ttl", 300),
        "accepting_members" => Map.get(attrs, "accepting_members", true),
        "witnessing" => Map.get(attrs, "witnessing", true),
        "enabled" => Map.get(attrs, "enabled", true)
      }

      if valid?(record, state),
        do: {:ok, %{state | settlement: record}},
        else: {:error, :invalid_settlement}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_settlement}
    end
  end

  @spec valid?(record :: term(), state :: map()) :: boolean()
  def valid?(nil, _state), do: true

  def valid?(r, state) when is_map(r) do
    Enum.sort(Map.keys(r)) == Enum.sort((@fields -- ["kind"]) ++ ~w(id version site_id)) and
      r["version"] == 1 and Scope.id?(r["id"]) and Scope.id?(r["name"]) and
      LocalRules.valid?(state.local_rules) and WorldProfile.valid?(r["profile"]) and
      references?(r, state) and policy?(r)
  end

  def valid?(_record, _state), do: false

  defp references?(r, state) do
    r["site_id"] == state.zone_id and npc?(state, r["merchant_id"]) and
      npc?(state, r["representative_id"]) and
      r["merchant_id"] != r["representative_id"] and Scope.id?(r["tradition"]) and
      is_binary(r["claim"]) and byte_size(r["claim"]) <= 2000 and String.valid?(r["claim"])
  end

  defp policy?(r) do
    integer?(r["price"], 2..1000) and integer?(r["scarcity_threshold"], 1..1000) and
      integer?(r["multiplier"], 1..10) and integer?(r["capacity"], 1..100) and
      integer?(r["quote_ttl"], 1..86_400) and
      Enum.all?(~w(accepting_members witnessing enabled), &is_boolean(r[&1]))
  end

  @spec stock(state :: map(), id :: String.t(), attrs :: map()) :: {:ok, map()} | {:error, atom()}
  def stock(%{settlement: nil}, _id, _attrs), do: {:error, :unsupported_capability}

  def stock(state, id, attrs) do
    owner = attrs["owner_id"]
    commodity = attrs["commodity"]
    quantity = attrs["quantity"]
    existing = state.items[id]

    with true <- state.settlement["enabled"],
         true <- Map.keys(attrs) -- ~w(kind name commodity quantity owner_id reason) == [],
         true <- Scope.id?(attrs["reason"]) and Map.has_key?(state.actors, owner),
         true <- Map.has_key?(state.local_rules["commodities"], commodity),
         true <-
           commodity != state.local_rules["currency"] or
             state.settlement["profile"]["exchange"] == "currency",
         true <- integer?(quantity, 0..1_000_000),
         true <-
           is_nil(existing) or
             (existing.commodity == commodity and existing.owner == {:actor, owner}),
         true <-
           Stock.balance(state, owner, commodity) - if(existing, do: existing.quantity, else: 0) +
             quantity <= 1_000_000 do
      item =
        struct(Item,
          id: id,
          name: state.local_rules["commodities"][commodity],
          commodity: commodity,
          quantity: quantity,
          owner: {:actor, owner},
          audience: {:actors, [owner]}
        )

      {:ok, %{state | items: Map.put(state.items, id, item)}}
    else
      _ -> {:error, :invalid_stock}
    end
  end

  @spec view(state :: map(), viewer :: map()) :: map() | nil
  def view(%{settlement: nil}, _viewer), do: nil

  def view(state, viewer) do
    s = state.settlement

    if Enum.all?(
         [s["merchant_id"], s["representative_id"]],
         &Audience.permits?(state.actors[&1].audience, viewer)
       ) do
      view =
        s
        |> Map.put("rules", state.local_rules)
        |> Map.put(
          "available_grain",
          Stock.balance(state, s["merchant_id"], state.local_rules["recipe"]["input"])
        )

      if viewer[:role] == :gm, do: view, else: Map.drop(view, ["witnessing"])
    end
  end

  defp migration(%{settlement: nil}, _profile, _enabled, _attrs), do: :ok

  defp migration(state, profile, enabled, attrs) do
    changing =
      state.settlement["profile"] != profile or (state.settlement["enabled"] and not enabled) or
        Enum.any?(~w(merchant_id representative_id), &(state.settlement[&1] != attrs[&1]))

    holdings =
      Enum.any?(state.items, fn {_id, item} ->
        not is_nil(item.commodity) and item.quantity > 0
      end)

    obligations =
      Enum.any?(state.knowledge, fn {_id, k} -> String.starts_with?(k.predicate, "local:") end)

    if changing and (holdings or obligations), do: {:error, :migration_required}, else: :ok
  end

  defp npc?(state, id),
    do:
      match?(
        %{kind: :npc, persona: %{"version" => version}} when version in [1, 2],
        state.actors[id]
      )

  defp integer?(n, range), do: is_integer(n) and n in range
end
