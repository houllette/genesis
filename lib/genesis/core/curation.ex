defmodule Genesis.Core.Curation do
  @moduledoc "Typed authoring reducer. Notes, plans and persona are never action facts or autonomous agents."
  alias Genesis.Core.{Actor, Item, Persona, Schedule, Scope, Settlement, State}

  @spec apply(state :: State.t(), id :: String.t(), attrs :: map(), character :: Actor.t() | nil) ::
          {:ok, State.t()} | {:error, atom()}
  def apply(state, id, attrs, character \\ nil) do
    with true <- Scope.id?(id) and valid_attrs?(attrs),
         {:ok, updated} <- record(state, id, attrs, character),
         {:ok, checked} <- State.restore(%{updated | revision: state.revision + 1}) do
      {:ok, checked}
    else
      {:error, :invalid_state} -> {:error, :invalid_record}
      {:error, _} = error -> error
      _ -> {:error, :invalid_record}
    end
  end

  defp valid_attrs?(%{"kind" => kind, "name" => name} = attrs),
    do:
      kind in ~w(zone npc pc item stock settlement schedule) and Scope.id?(name) and
        Map.keys(attrs) -- allowed_fields(kind) == []

  defp valid_attrs?(_attrs), do: false

  defp allowed_fields("zone"), do: ~w(kind name description)

  defp allowed_fields("npc"),
    do: ~w(kind name visibility companion_policy) ++ Persona.editable_fields()

  defp allowed_fields("pc"), do: ~w(kind name)
  defp allowed_fields("schedule"), do: Schedule.fields()
  defp allowed_fields("item"), do: ~w(kind name quantity visibility)
  defp allowed_fields("stock"), do: ~w(kind name commodity quantity owner_id reason)

  defp allowed_fields("settlement"),
    do:
      ~w(kind name profile merchant_id representative_id tradition claim price scarcity_threshold multiplier capacity quote_ttl accepting_members witnessing enabled)

  defp record(state, id, %{"kind" => "settlement"} = attrs, _character),
    do: Settlement.configure(state, id, attrs)

  defp record(state, id, %{"kind" => "schedule"} = attrs, _character),
    do: Schedule.configure(state, id, attrs)

  defp record(state, id, %{"kind" => "stock"} = attrs, _character),
    do: Settlement.stock(state, id, attrs)

  defp record(state, id, %{"kind" => "zone"} = attrs, _character) when id == state.zone_id,
    do: {:ok, %{state | name: attrs["name"], description: Map.get(attrs, "description", "")}}

  defp record(state, id, %{"kind" => "npc"} = attrs, _character) do
    existing = state.actors[id] || struct(Actor, id: id, name: attrs["name"], kind: :npc)

    if existing.kind == :npc do
      actor = %{
        existing
        | name: attrs["name"],
          revision: existing.revision + 1,
          audience: audience(attrs, existing.audience),
          companion_policy: Map.get(attrs, "companion_policy", existing.companion_policy),
          persona: Persona.edit(id, existing.persona, attrs)
      }

      {:ok, %{state | actors: Map.put(state.actors, id, actor)}}
    else
      {:error, :wrong_kind}
    end
  end

  defp record(state, id, %{"kind" => "pc"} = attrs, %Actor{kind: :pc} = character) do
    existing = state.actors[id] || character

    if existing.kind == :pc do
      actor = %{existing | id: id, name: attrs["name"], revision: existing.revision + 1}
      {:ok, %{state | actors: Map.put(state.actors, id, actor)}}
    else
      {:error, :wrong_kind}
    end
  end

  defp record(state, id, %{"kind" => "item"} = attrs, _character) do
    existing =
      state.items[id] || struct(Item, id: id, name: attrs["name"], owner: {:zone, state.zone_id})

    item = %{
      existing
      | name: attrs["name"],
        quantity: Map.get(attrs, "quantity", existing.quantity),
        audience: audience(attrs, existing.audience)
    }

    if is_nil(existing.commodity),
      do: {:ok, %{state | items: Map.put(state.items, id, item)}},
      else: {:error, :use_stock_controls}
  end

  defp record(_state, _id, _attrs, _character), do: {:error, :invalid_record}
  defp audience(%{"visibility" => "private"}, _previous), do: :gm
  defp audience(%{"visibility" => "public"}, _previous), do: :public
  defp audience(%{"visibility" => "unchanged"}, previous), do: previous
  defp audience(attrs, previous) when not is_map_key(attrs, "visibility"), do: previous
  defp audience(_attrs, _previous), do: :invalid
end
