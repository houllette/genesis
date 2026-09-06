defmodule Genesis.Core.RecordedChange do
  @moduledoc "Checked field deltas for incorporation. Never replaces a candidate with a terminal adventure snapshot."
  alias Genesis.Core.State

  @mechanical [
    :actors,
    :items,
    :knowledge,
    :actor_refs,
    :settlement,
    :local_rules,
    :actions,
    :context_rules,
    :name,
    :description,
    :timeline
  ]

  @spec apply(candidate :: map(), before :: map(), next :: map(), effect :: map()) :: term()
  def apply(candidate, before, next, effect) do
    before = rescope(before, candidate.scope)
    next = rescope(next, candidate.scope)
    read_fields = if is_nil(effect[:actor_id]), do: [], else: @mechanical

    with true <- Enum.all?(read_fields, &(Map.fetch!(candidate, &1) == Map.fetch!(before, &1))),
         {:ok, changed} <- changes(candidate, before, next) do
      events =
        if Map.has_key?(effect, :id),
          do: candidate.events ++ [%{effect | scope: candidate.scope}],
          else: candidate.events

      {:ok, %{changed | events: events}}
    else
      _ -> {:error, :recorded_dependency_changed}
    end
  end

  @spec equivalent?(candidate :: map(), recorded :: map()) :: boolean()
  def equivalent?(candidate, recorded) do
    recorded = rescope(recorded, candidate.scope)
    Enum.all?(@mechanical, &(Map.fetch!(candidate, &1) == Map.fetch!(recorded, &1)))
  end

  defp changes(candidate, before, next) do
    Enum.reduce_while(@mechanical, {:ok, candidate}, fn field, {:ok, acc} ->
      first = Map.fetch!(before, field)
      last = Map.fetch!(next, field)

      cond do
        first == last -> {:cont, {:ok, acc}}
        Map.fetch!(acc, field) == first -> {:cont, {:ok, Map.put(acc, field, last)}}
        true -> {:halt, {:error, :recorded_dependency_changed}}
      end
    end)
  end

  @spec rescope(state :: State.t(), scope :: map()) :: State.t()
  def rescope(state, scope),
    do: %{
      state
      | scope: scope,
        knowledge: Map.new(state.knowledge, fn {id, value} -> {id, %{value | scope: scope}} end),
        events: Enum.map(state.events, &Map.put(&1, :scope, scope))
    }

  @spec publish(state :: State.t(), original :: State.t(), target :: integer(), mapping :: map()) ::
          term()
  def publish(state, original, target, mapping) do
    next = rescope(state, original.scope)

    knowledge =
      Map.new(next.knowledge, fn {id, value} ->
        {id, %{value | source_ids: sources(value.source_ids, mapping)}}
      end)

    actors =
      Map.new(next.actors, fn {id, actor} ->
        actor =
          if actor.commitment,
            do: %{
              actor
              | commitment: Map.update!(actor.commitment, "source_id", &Map.get(mapping, &1, &1))
            },
            else: actor

        {id, actor}
      end)

    events =
      Enum.map(next.events, fn event ->
        event
        |> Map.update!(:id, &Map.get(mapping, &1, &1))
        |> Map.put(:revision, original.revision + 1)
        |> Map.update(:source_ids, [], &sources(&1, mapping))
      end)

    State.restore(%{
      next
      | actors: actors,
        knowledge: knowledge,
        events: events,
        time: %{original.time | value: target},
        elapsed: 0,
        status: :active,
        revision: original.revision + 1
    })
  end

  defp sources(values, mapping), do: Enum.map(values, &Map.get(mapping, &1, &1))
end
