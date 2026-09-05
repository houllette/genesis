defmodule Genesis.Core.Incorporation do
  @moduledoc "The phase-04 single-zone zero-duration projection. Apply only checked changed fields to the pinned base."
  alias Genesis.Core.State

  @spec project(
          published :: State.t(),
          working_base :: State.t(),
          working :: State.t(),
          mapping :: map()
        ) :: {:ok, State.t()} | {:error, atom()}
  def project(published, working_base, working, mapping) do
    with true <- published.scope.kind == :published and working.scope.kind == :experience,
         true <- working.scope == working_base.scope and working.zone_id == published.zone_id,
         true <- working.elapsed == 0 and working.time == published.time,
         true <-
           working_base.rules_ref == published.rules_ref and
             working.rules_ref == published.rules_ref,
         {:ok, updated} <- changed_fields(published, working_base, working, mapping) do
      events =
        Enum.map(working.events, fn event ->
          event
          |> Map.put(:id, Map.fetch!(mapping, event.id))
          |> Map.put(:scope, published.scope)
          |> Map.put(:revision, published.revision + 1)
          |> Map.update!(:source_ids, &map_sources(&1, mapping))
        end)

      State.restore(%{
        updated
        | revision: published.revision + 1,
          events: published.events ++ events,
          elapsed: 0,
          status: :active
      })
    else
      _ -> {:error, :incorporation_conflict}
    end
  end

  defp changed_fields(published, base, working, mapping) do
    Enum.reduce_while([:actors, :items, :knowledge], {:ok, published}, fn field,
                                                                          {:ok, candidate} ->
      original = Map.fetch!(base, field)
      current = Map.fetch!(working, field)
      updates = Enum.filter(current, fn {id, value} -> original[id] != value end)

      checked =
        Enum.all?(original, fn {id, value} ->
          Map.get(Map.fetch!(published, field), id) == normalize(value, published.scope, %{})
        end)

      if checked and Enum.all?(Map.keys(original), &Map.has_key?(current, &1)) do
        values = merge_updates(updates, Map.fetch!(candidate, field), published.scope, mapping)

        {:cont, {:ok, Map.put(candidate, field, values)}}
      else
        {:halt, {:error, :base_conflict}}
      end
    end)
  end

  defp merge_updates(updates, values, scope, mapping) do
    Enum.reduce(updates, values, fn {id, value}, acc ->
      Map.put(acc, id, normalize(value, scope, mapping))
    end)
  end

  defp normalize(%{scope: _scope, source_ids: sources} = value, scope, mapping),
    do: %{value | scope: scope, source_ids: map_sources(sources, mapping)}

  defp normalize(value, _scope, _mapping), do: value
  defp map_sources(sources, mapping), do: Enum.map(sources, &Map.get(mapping, &1, &1))
end
