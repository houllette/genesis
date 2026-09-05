defmodule Genesis.Core.Progression do
  @moduledoc "Pure milestone, defeat and retirement rules. Awards are sourced facts in the existing ledger."
  alias Genesis.Core.{Knowledge, Scope, State}

  @spec award(state :: State.t(), actor_id :: String.t(), policy :: map(), inputs :: map()) ::
          {:ok, State.t(), [map()]} | {:error, atom()}
  def award(state, actor_id, policy, inputs) do
    milestone = policy["milestone"]
    predicate = "award:" <> milestone["id"]

    with :ok <- eligible(state, actor_id, inputs),
         [] <- facts(state, actor_id, predicate),
         [_ | _] = deeds <-
           Enum.filter(facts(state, actor_id, milestone["fact"]), &(&1.value == true)) do
      inputs = Map.put(inputs, :source_ids, Enum.map(deeds, & &1.id) |> Enum.sort())
      record(state, actor_id, inputs, predicate, milestone["award"], "milestone")
    else
      {:error, _reason} = error -> error
      _ -> {:error, :ineligible_award}
    end
  end

  @doc "Exceptional risk requires a prior actor/scope/policy-bound consent value; absence is nonlethal."
  @spec defeat(
          state :: State.t(),
          actor_id :: String.t(),
          policy :: map(),
          consent :: map() | nil,
          inputs :: map()
        ) ::
          {:ok, State.t(), [map()]} | {:error, atom()}
  def defeat(state, actor_id, policy, consent, inputs) do
    with :ok <- eligible(state, actor_id, inputs) do
      lethal = consent?(consent, state, actor_id, policy)
      state = if lethal, do: put_in(state.actors[actor_id].alive, false), else: state

      record(
        state,
        actor_id,
        inputs,
        "defeated",
        if(lethal, do: "dead", else: "injured"),
        "defeat"
      )
    end
  end

  @doc "Transfers only explicitly selected owned items. Private memories stay with the retired actor."
  @spec retire(
          state :: State.t(),
          actor_id :: String.t(),
          successor_id :: String.t(),
          item_ids :: [String.t()],
          inputs :: map()
        ) ::
          {:ok, State.t(), [map()]} | {:error, atom()}
  def retire(state, actor_id, successor_id, item_ids, inputs) do
    with :ok <- eligible(state, actor_id, inputs),
         true <- successor_id != actor_id,
         %{alive: true, retired: false} <- state.actors[successor_id],
         true <- transferable?(state, actor_id, item_ids) do
      items =
        Enum.reduce(item_ids, state.items, fn id, items ->
          Map.update!(items, id, &%{&1 | owner: {:actor, successor_id}})
        end)

      state =
        %{state | items: items}
        |> put_in([Access.key(:actors), actor_id, Access.key(:retired)], true)

      record(state, actor_id, inputs, "retired", "offstage", "retirement")
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_transfer}
    end
  end

  defp eligible(state, actor_id, %{scope: scope, expected_revision: revision, event_id: event_id}) do
    cond do
      scope != state.scope or scope.kind not in [:experience, :rehearsal] ->
        {:error, :wrong_scope}

      revision != state.revision ->
        {:error, :stale_revision}

      state.status != :active ->
        {:error, :paused}

      not valid_event_id?(event_id) ->
        {:error, :invalid_event}

      Enum.any?(state.events, &(&1.id == event_id)) ->
        {:error, :duplicate_event}

      not match?(%{alive: true, retired: false}, state.actors[actor_id]) ->
        {:error, :unavailable}

      true ->
        :ok
    end
  end

  defp eligible(_state, _actor_id, _inputs), do: {:error, :invalid_envelope}
  defp valid_event_id?(id), do: Scope.id?(id) and byte_size(id) <= 100

  defp facts(state, actor, predicate),
    do:
      state.knowledge
      |> Map.values()
      |> Enum.filter(fn fact ->
        fact.kind == :fact and fact.scope == state.scope and fact.subject_id == actor and
          fact.predicate == predicate
      end)

  defp consent?(
         %{
           actor_id: actor,
           scope: scope,
           policy_version: version,
           risk: "permadeath",
           accepted: true,
           revision: revision
         },
         state,
         actor,
         policy
       ),
       do:
         scope == state.scope and version == policy["policy_version"] and
           revision == state.revision

  defp consent?(_consent, _state, _actor, _policy), do: false

  defp transferable?(state, actor, ids) when is_list(ids) and length(ids) <= 100,
    do:
      Enum.uniq(ids) == ids and
        Enum.all?(ids, &match?(%{owner: {:actor, ^actor}}, state.items[&1]))

  defp transferable?(_state, _actor, _ids), do: false

  defp record(state, actor_id, inputs, predicate, value, type) do
    id = inputs.event_id
    audience = {:actors, [actor_id]}

    fact = %Knowledge{
      id: id <> "/fact",
      kind: :fact,
      subject_id: actor_id,
      predicate: predicate,
      value: value,
      scope: state.scope,
      source_ids: [id],
      audience: audience,
      occurred_at: state.time.value,
      recorded_at: Map.get(inputs, :recorded_at)
    }

    effect = %{
      id: id,
      actor_id: actor_id,
      type: type,
      target_id: actor_id,
      scope: state.scope,
      source_ids: Map.get(inputs, :source_ids, []),
      result: %{"outcome" => value},
      audience: audience,
      revision: state.revision + 1,
      occurred_at: state.time.value
    }

    state = %{
      state
      | knowledge: Map.put(state.knowledge, fact.id, fact),
        events: state.events ++ [effect],
        revision: state.revision + 1
    }

    state = update_in(state.actors[actor_id].revision, &(&1 + 1))
    {:ok, state, [effect]}
  end
end
