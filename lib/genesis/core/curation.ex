defmodule Genesis.Core.Curation do
  @moduledoc "Typed authoring reducer. Notes, plans and persona are never action facts or autonomous agents."
  alias Genesis.Core.{Actor, Item, Scope, State}

  @spec apply(state :: State.t(), id :: String.t(), attrs :: map(), character :: Actor.t() | nil) ::
          {:ok, State.t()} | {:error, atom()}
  def apply(state, id, attrs, character \\ nil) do
    with true <- Scope.id?(id) and valid_attrs?(attrs),
         {:ok, updated} <- record(state, id, attrs, character),
         {:ok, checked} <- State.restore(%{updated | revision: state.revision + 1}) do
      {:ok, checked}
    else
      _ -> {:error, :invalid_record}
    end
  end

  defp valid_attrs?(%{"kind" => kind, "name" => name} = attrs),
    do:
      kind in ~w(zone npc pc item) and Scope.id?(name) and
        Map.keys(attrs) -- allowed_fields(kind) == []

  defp valid_attrs?(_attrs), do: false

  defp allowed_fields("zone"), do: ~w(kind name description)
  defp allowed_fields("npc"), do: ~w(kind name temperament goal visibility)
  defp allowed_fields("pc"), do: ~w(kind name)
  defp allowed_fields("item"), do: ~w(kind name quantity visibility)

  defp record(state, id, %{"kind" => "zone"} = attrs, _character) when id == state.zone_id,
    do: {:ok, %{state | name: attrs["name"], description: Map.get(attrs, "description", "")}}

  defp record(state, id, %{"kind" => "npc"} = attrs, _character) do
    existing = state.actors[id] || struct(Actor, id: id, name: attrs["name"], kind: :npc)

    if existing.kind == :npc do
      actor = %{
        existing
        | name: attrs["name"],
          revision: existing.revision + 1,
          audience: audience(attrs),
          persona: %{
            "version" => 1,
            "temperament" => Map.get(attrs, "temperament", "Watchful"),
            "goal" => Map.get(attrs, "goal", "Protect their place in the community"),
            "agency" => "dormant"
          }
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
        audience: audience(attrs)
    }

    {:ok, %{state | items: Map.put(state.items, id, item)}}
  end

  defp record(_state, _id, _attrs, _character), do: {:error, :invalid_record}
  defp audience(%{"visibility" => "private"}), do: :gm
  defp audience(%{"visibility" => "public"}), do: :public
  defp audience(attrs) when not is_map_key(attrs, "visibility"), do: :public
  defp audience(_attrs), do: :invalid
end
