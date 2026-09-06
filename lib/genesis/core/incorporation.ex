defmodule Genesis.Core.Incorporation do
  @moduledoc "Zero-duration whole-footprint projection. Relocation is legal only when identities are conserved across all zones."
  alias Genesis.Core.{Scope, State}
  @collections [:actors, :items, :knowledge]
  @fixed [
    :zone_id,
    :time,
    :rules_ref,
    :local_rules,
    :settlement,
    :name,
    :description,
    :actions,
    :context_rules,
    :timeline
  ]

  @spec project(
          published :: State.t(),
          working_base :: State.t(),
          working :: State.t(),
          mapping :: map()
        ) ::
          {:ok, State.t()} | {:error, atom()}
  def project(published, working_base, working, mapping) do
    with {:ok, [candidate]} <-
           project_many(
             [%{published: published, working_base: working_base, working: working}],
             mapping
           ),
         do: {:ok, candidate}
  end

  @spec project_many(zones :: [map()], mapping :: map()) :: {:ok, [State.t()]} | {:error, atom()}
  def project_many(zones, mapping) when is_list(zones) and is_map(mapping) do
    with true <- length(zones) in 1..8 and Enum.all?(zones, &valid_zone?/1),
         true <- same_footprint?(zones),
         true <- conserved?(zones),
         true <- valid_mapping?(zones, mapping) do
      project_zones(zones, mapping)
    else
      _ -> {:error, :incorporation_conflict}
    end
  end

  def project_many(_zones, _mapping), do: {:error, :incorporation_conflict}

  defp project_zones(zones, mapping) do
    Enum.reduce_while(zones, {:ok, []}, fn zone, {:ok, acc} ->
      case project_zone(zone, mapping) do
        {:ok, candidate} -> {:cont, {:ok, acc ++ [candidate]}}
        _ -> {:halt, {:error, :incorporation_conflict}}
      end
    end)
  end

  defp valid_zone?(%{published: p, working_base: b, working: w}) do
    Enum.all?([p, b, w], &match?({:ok, _}, State.restore(&1))) and
      p.scope.kind == :published and w.scope.kind == :experience and w.scope == b.scope and
      w.elapsed == 0 and b.elapsed == 0 and
      Enum.all?(
        @fixed,
        &(Map.fetch!(p, &1) == Map.fetch!(b, &1) and Map.fetch!(b, &1) == Map.fetch!(w, &1))
      ) and
      Enum.all?(@collections, fn field ->
        Map.fetch!(p, field) == normalize_values(Map.fetch!(b, field), p.scope, %{})
      end)
  end

  defp valid_zone?(_zone), do: false

  defp same_footprint?(zones) do
    [first | _] = zones
    ids = Enum.map(zones, & &1.published.zone_id)

    length(Enum.uniq(ids)) == length(ids) and
      Enum.all?(
        zones,
        &(&1.published.scope == first.published.scope and &1.working.scope == first.working.scope)
      ) and
      first.published.scope.world_id == first.working.scope.world_id and
      first.published.scope.generation == first.working.scope.generation
  end

  defp conserved?(zones) do
    original = identities(zones, :published)
    current = identities(zones, :working)

    unique?(original) and unique?(current) and
      MapSet.subset?(MapSet.new(original), MapSet.new(current))
  end

  defp identities(zones, key),
    do:
      for(
        zone <- zones,
        field <- @collections,
        id <- Map.keys(Map.fetch!(Map.fetch!(zone, key), field)),
        do: {field, id}
      )

  defp unique?(ids), do: length(ids) == MapSet.size(MapSet.new(ids))

  defp valid_mapping?(zones, mapping) do
    events = Enum.flat_map(zones, & &1.working.events)
    prior = MapSet.new(Enum.flat_map(zones, & &1.published.events), & &1.id)

    unique?(Enum.map(events, & &1.id)) and unique?(Map.values(mapping)) and
      Enum.all?(mapping, fn {from, to} -> Scope.id?(from) and Scope.id?(to) end) and
      Enum.all?(Map.values(mapping), &(not MapSet.member?(prior, &1))) and
      Enum.all?(events, &(Map.has_key?(mapping, &1.id) and valid_event?(&1)))
  end

  defp valid_event?(%{revision: revision, source_ids: sources})
       when is_integer(revision) and is_list(sources),
       do: Enum.all?(sources, &Scope.id?/1)

  defp valid_event?(_event), do: false

  defp project_zone(%{published: published, working: working}, mapping) do
    updated =
      Enum.reduce(@collections, published, fn field, acc ->
        Map.put(
          acc,
          field,
          normalize_values(Map.fetch!(working, field), published.scope, mapping)
        )
      end)

    events =
      Enum.map(working.events, fn event ->
        %{
          event
          | id: Map.fetch!(mapping, event.id),
            scope: published.scope,
            revision: published.revision + 1,
            source_ids: map_sources(event.source_ids, mapping)
        }
      end)

    State.restore(%{
      updated
      | revision: published.revision + 1,
        actor_refs: working.actor_refs,
        events: published.events ++ events,
        elapsed: 0,
        status: :active
    })
  end

  defp normalize_values(values, scope, mapping),
    do: Map.new(values, fn {id, value} -> {id, normalize(value, scope, mapping)} end)

  defp normalize(%{scope: _scope, source_ids: sources} = value, scope, mapping),
    do: %{value | scope: scope, source_ids: map_sources(sources, mapping)}

  defp normalize(%{commitment: commitment} = actor, _scope, mapping) when is_map(commitment),
    do: %{actor | commitment: Map.update!(commitment, "source_id", &Map.get(mapping, &1, &1))}

  defp normalize(value, _scope, _mapping), do: value
  defp map_sources(sources, mapping), do: Enum.map(sources, &Map.get(mapping, &1, &1))
end
