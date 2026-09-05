defmodule Genesis.Core.Context do
  @moduledoc "Bounded, data-driven context selection from current actor, deed and companion state."
  alias Genesis.Core.{Audience, Scope}

  @spec valid?(rules :: term()) :: boolean()
  def valid?(rules) when is_list(rules) and length(rules) <= 32,
    do:
      Enum.all?(rules, &valid_rule?/1) and
        length(Enum.uniq_by(rules, & &1["id"])) == length(rules)

  def valid?(_rules), do: false

  defp valid_rule?(
         %{"id" => id, "priority" => priority, "when" => condition, "set" => setters} = rule
       ),
       do:
         map_size(rule) == 4 and Scope.id?(id) and is_integer(priority) and priority in 0..1000 and
           valid_condition?(condition) and valid_setters?(setters)

  defp valid_rule?(_rule), do: false

  defp valid_condition?(%{"kind" => kind, "key" => key} = condition)
       when kind in ["trait", "deed"],
       do: map_size(condition) == 2 and Scope.id?(key)

  defp valid_condition?(
         %{"kind" => "companion", "key" => key, "relationship" => relation} = condition
       ),
       do: map_size(condition) == 3 and Scope.id?(key) and relation in ["allied", "hostile"]

  defp valid_condition?(_condition), do: false

  defp valid_setters?(setters) when is_map(setters) and map_size(setters) in 1..2,
    do:
      Enum.all?(setters, fn
        {"cost", cost} -> is_integer(cost) and cost in 0..1_000_000
        {"outcome", outcome} -> outcome in ["admitted", "confrontation"]
        _ -> false
      end)

  defp valid_setters?(_setters), do: false

  @spec resolve(
          state :: Genesis.Core.State.t(),
          actor_id :: String.t(),
          observer_id :: String.t(),
          defaults :: map()
        ) :: map()
  def resolve(state, actor_id, observer_id, defaults) do
    state.context_rules
    |> Enum.sort_by(&{&1["priority"], &1["id"]})
    |> Enum.reduce(Map.merge(defaults, %{sources: [], variants: []}), fn rule, result ->
      case sources(state, actor_id, observer_id, rule["when"]) do
        [] ->
          result

        sources ->
          result
          |> Map.merge(rule["set"])
          |> Map.update!(:sources, &Enum.uniq(&1 ++ sources))
          |> Map.update!(:variants, &(&1 ++ [rule["id"]]))
      end
    end)
  end

  defp sources(state, actor_id, observer_id, %{"kind" => "trait", "key" => key}) do
    actor = state.actors[actor_id]

    if key in actor.traits and Audience.permits?(actor.audience, %{actor_id: observer_id}),
      do: [actor.id],
      else: []
  end

  defp sources(state, actor_id, observer_id, %{"kind" => "deed", "key" => key}) do
    state.knowledge
    |> Map.values()
    |> Enum.filter(fn record ->
      record.kind == :fact and record.subject_id == actor_id and record.predicate == key and
        record.value == true and record.scope == state.scope and
        Audience.permits?(record.audience, %{actor_id: observer_id})
    end)
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp sources(state, actor_id, observer_id, %{
         "kind" => "companion",
         "key" => key,
         "relationship" => relationship
       }) do
    state.actors
    |> Map.values()
    |> Enum.filter(&eligible_companion?(&1, actor_id, observer_id, key))
    |> Enum.flat_map(fn companion ->
      state.knowledge
      |> Map.values()
      |> Enum.filter(fn record ->
        record.kind == :relationship and record.subject_id == observer_id and
          record.object_id == companion.id and record.predicate == "standing" and
          record.value == relationship and
          record.scope == state.scope and
          Audience.permits?(record.audience, %{actor_id: observer_id})
      end)
      |> Enum.map(& &1.id)
    end)
    |> Enum.sort()
  end

  defp sources(_state, _actor_id, _observer_id, _condition), do: []

  defp eligible_companion?(companion, actor_id, observer_id, key),
    do:
      companion.kind == :npc and companion.companion_of == actor_id and companion.alive and
        not companion.retired and Map.get(companion.skills, key, 0) > 0 and
        Audience.permits?(companion.audience, %{actor_id: observer_id})
end
