defmodule Genesis.Content.Comparison do
  @moduledoc "Pure human-readable differences between equally authorized checkpoint and working projections."

  @spec changes(before :: map(), working :: map()) :: [map()]
  def changes(before, working) do
    actor_changes(before, working) ++
      item_changes(before, working) ++ fact_changes(before, working)
  end

  defp actor_changes(before, working) do
    compare(
      before.actors,
      working.actors,
      fn actor ->
        %{label: actor.name, value: actor_status(actor)}
      end,
      "actor"
    )
  end

  defp actor_status(actor) do
    status = if actor.alive, do: "Alive", else: "Defeated"

    resources =
      Map.get(actor, :resources, %{})
      |> Enum.sort()
      |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{value}" end)

    Enum.join(Enum.reject([status, resources], &(&1 == "")), " · ")
  end

  defp item_changes(before, working) do
    old = Enum.map(before.items, &item(&1, before))
    current = Enum.map(working.items, &item(&1, working))
    compare(old, current, & &1, "item")
  end

  defp item(item, view),
    do: %{id: item.id, label: item.name, value: "#{item.quantity} · #{owner(item.owner, view)}"}

  defp owner({:zone, _id}, _view), do: "at this place"
  defp owner({:actor, id}, view), do: "carried by " <> actor_name(view, id)

  defp fact_changes(before, working) do
    old = Enum.map(before.knowledge, &fact(&1, before))
    current = Enum.map(working.knowledge, &fact(&1, working))
    compare(old, current, & &1, "knowledge")
  end

  defp fact(record, view),
    do: %{
      id: record.id,
      label:
        "#{actor_name(view, record.subject_id)} · #{String.replace(record.predicate, "_", " ")} (#{record.kind})",
      value: value(record.value)
    }

  defp actor_name(view, id),
    do:
      Enum.find_value(view.actors, "an unseen actor", fn actor ->
        if actor.id == id, do: actor.name
      end)

  defp value(true), do: "Yes"
  defp value(false), do: "No"
  defp value(value), do: to_string(value)

  defp compare(before, working, projection, prefix) do
    prior = Map.new(before, &{&1.id, projection.(&1)})

    changed =
      Enum.flat_map(working, fn record ->
        next = projection.(record)
        row(prior[record.id], next, prefix <> "-" <> record.id)
      end)

    removed =
      before
      |> Enum.reject(fn record -> Enum.any?(working, &(&1.id == record.id)) end)
      |> Enum.map(fn record ->
        old = projection.(record)

        %{
          id: prefix <> "-" <> record.id,
          label: old.label,
          published: old.value,
          working: "Not present at this place"
        }
      end)

    changed ++ removed
  end

  defp row(same, same, _id), do: []

  defp row(nil, next, id),
    do: [%{id: id, label: next.label, published: "Not recorded", working: next.value}]

  defp row(before, next, id),
    do: [%{id: id, label: next.label, published: before.value, working: next.value}]
end
