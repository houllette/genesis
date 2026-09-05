defmodule Genesis.Core.Scene do
  @moduledoc "Pure bounded scene actions; callers supply identity, revision, event ID and audit time."
  alias Genesis.Core.{
    Audience,
    Check,
    Companions,
    Context,
    FictionalTime,
    Knowledge,
    LocalAction,
    Proposal,
    Scope,
    State
  }

  @spec reduce(state :: State.t(), actor_id :: String.t(), intent :: map(), inputs :: map()) ::
          {:ok, State.t(), [map()]} | {:error, atom()}
  def reduce(state, actor_id, intent, inputs) when is_map(intent) do
    with :ok <- envelope(state, inputs) do
      cond do
        Companions.handles?(Map.get(intent, :type)) ->
          Companions.reduce(state, actor_id, intent, inputs)

        LocalAction.handles?(Map.get(intent, :type)) ->
          LocalAction.reduce(state, actor_id, intent, inputs)

        true ->
          reduce_scene(state, actor_id, intent, inputs)
      end
    end
  end

  def reduce(_state, _actor_id, _intent, _inputs), do: {:error, :unsupported_action}

  defp reduce_scene(state, actor_id, intent, inputs) do
    with {:ok, terms} <- terms(state, actor_id, intent),
         {:ok, terms} <- resolve_roll(state, actor_id, terms, inputs.draws),
         {:ok, time} <-
           FictionalTime.advance(state.time, %{unit: :second, value: terms["duration"]}) do
      commit(state, actor_id, intent, inputs, terms, time)
    end
  end

  @spec propose(state :: State.t(), actor_id :: String.t(), intent :: map(), id :: String.t()) ::
          {:ok, Proposal.t()} | {:clarify, :target_id} | {:error, atom()}
  def propose(state, actor_id, %{type: type} = intent, id) do
    cond do
      not Scope.id?(id) ->
        {:error, :invalid_proposal}

      LocalAction.handles?(type) ->
        LocalAction.propose(state, actor_id, intent, id)

      Companions.handles?(type) ->
        Companions.propose(state, actor_id, intent, id)

      is_nil(action(state, type)) ->
        {:error, :unsupported_action}

      not Map.has_key?(intent, :target_id) and map_size(intent) == 1 ->
        {:clarify, :target_id}

      true ->
        with {:ok, terms} <- terms(state, actor_id, intent) do
          {:ok,
           %Proposal{
             id: id,
             scope: state.scope,
             actor_id: actor_id,
             revision: state.revision,
             intent: intent,
             terms: terms,
             rules_ref: state.rules_ref
           }}
        end
    end
  end

  def propose(_state, _actor_id, _intent, _id), do: {:error, :unsupported_action}

  @spec confirm(state :: State.t(), proposal :: Proposal.t(), inputs :: map()) ::
          {:ok, State.t(), [map()]} | {:error, atom()}
  def confirm(state, %Proposal{} = proposal, inputs) do
    with :ok <- revalidate(state, proposal) do
      reduce(state, proposal.actor_id, proposal.intent, inputs)
    end
  end

  def confirm(_state, _proposal, _inputs), do: {:error, :stale_proposal}

  @spec revalidate(state :: State.t(), proposal :: Proposal.t()) :: :ok | {:error, atom()}
  def revalidate(state, proposal) do
    if LocalAction.handles?(proposal.intent.type) do
      LocalAction.revalidate(state, proposal)
    else
      with {:ok, current} <- propose(state, proposal.actor_id, proposal.intent, proposal.id),
           true <- current == proposal do
        :ok
      else
        _ -> {:error, :stale_proposal}
      end
    end
  end

  @doc "Only disclosable terms leave the authority; the complete proposal stays server-side."
  @spec proposal_view(proposal :: Proposal.t()) :: map()
  def proposal_view(proposal),
    do: %{
      id: proposal.id,
      revision: proposal.revision,
      terms:
        Map.take(proposal.terms, [
          "cost",
          "resource",
          "duration",
          "summary",
          "unit_price",
          "total",
          "unit",
          "expires_at"
        ])
    }

  @spec effects_for(effects :: [map()], viewer :: map()) :: [map()]
  def effects_for(effects, viewer) do
    effects
    |> Enum.filter(&Audience.permits?(&1.audience, viewer))
    |> Enum.map(
      &Map.take(&1, [:id, :type, :actor_id, :target_id, :result, :revision, :occurred_at])
    )
  end

  defp envelope(
         state,
         %{scope: scope, expected_revision: revision, event_id: id, draws: draws} = inputs
       ) do
    cond do
      scope != state.scope ->
        {:error, :wrong_scope}

      revision != state.revision ->
        {:error, :stale_revision}

      not event_id?(id) ->
        {:error, :invalid_event}

      not is_list(draws) ->
        {:error, :invalid_draws}

      not valid_recording?(Map.get(inputs, :recorded_at)) ->
        {:error, :invalid_recording_time}

      event_exists?(state, id) ->
        {:error, :duplicate_event}

      true ->
        :ok
    end
  end

  defp envelope(_state, _inputs), do: {:error, :invalid_envelope}
  defp event_id?(id), do: Scope.id?(id) and byte_size(id) <= 100

  defp event_exists?(state, id),
    do:
      Enum.any?(state.events, &(&1.id == id)) or
        Map.has_key?(state.knowledge, id <> "/fact")

  defp valid_recording?(%DateTime{utc_offset: 0, std_offset: 0, time_zone: "Etc/UTC"}), do: true
  defp valid_recording?(nil), do: true
  defp valid_recording?(_time), do: false

  defp terms(%{scope: %{kind: :published}}, _actor_id, _intent), do: {:error, :read_only_scope}
  defp terms(%{status: :paused}, _actor_id, _intent), do: {:error, :paused}

  defp terms(state, actor_id, %{type: type, target_id: target} = intent)
       when map_size(intent) == 2 do
    with %{alive: true, retired: false} = actor <- state.actors[actor_id],
         %{} = action <- action(state, type),
         :ok <- target_available(state, actor_id, target, action["kind"]),
         {:ok, result} <- resolve_terms(state, actor_id, target, action),
         true <- valid_terms?(result),
         true <- Map.get(actor.resources, result["resource"], 0) >= result["cost"] do
      {:ok, result}
    else
      nil -> {:error, :unsupported_action}
      {:error, _reason} = error -> error
      false -> {:error, :insufficient_resources}
      _ -> {:error, :unavailable}
    end
  end

  defp terms(_state, _actor_id, _intent), do: {:error, :unsupported_action}

  # Returning a carried ordinary item is the inverse of the bundle's take
  # capability, not an inventory editor. Commodity lots stay in owned stores.
  defp action(state, "drop") do
    case Enum.find_value(state.actions, &take_action/1) do
      nil -> nil
      take -> Map.merge(take, %{"kind" => "drop", "cost" => 0, "duration" => 0})
    end
  end

  defp action(state, type), do: state.actions[type]
  defp take_action({_id, %{"kind" => "take"} = action}), do: action
  defp take_action(_entry), do: nil

  defp target_available(state, actor, target, "drop") do
    case state.items[target] do
      %{owner: {:actor, ^actor}, commodity: nil, audience: audience} ->
        if Audience.permits?(audience, %{actor_id: actor}), do: :ok, else: {:error, :unavailable}

      _ ->
        {:error, :unavailable}
    end
  end

  defp target_available(state, actor_id, target, "take") do
    case state.items[target] do
      %{owner: {:zone, zone}, audience: audience, quantity: quantity}
      when zone == state.zone_id and quantity > 0 ->
        if Audience.permits?(audience, %{actor_id: actor_id}),
          do: :ok,
          else: {:error, :unavailable}

      _ ->
        {:error, :unavailable}
    end
  end

  defp target_available(state, actor_id, target, kind) when kind in ["deed", "access", "check"] do
    case state.actors[target] do
      %{kind: :npc, alive: true, retired: false, audience: audience} ->
        if Audience.permits?(audience, %{actor_id: actor_id}),
          do: :ok,
          else: {:error, :unavailable}

      _ ->
        {:error, :unavailable}
    end
  end

  defp target_available(_state, _actor_id, _target, _kind), do: {:error, :unsupported_action}

  defp resolve_terms(state, actor_id, target, %{"kind" => "access"} = action),
    do: {:ok, Context.resolve(state, actor_id, target, action)}

  defp resolve_terms(state, actor_id, _target, %{"kind" => "check"} = action) do
    with {:ok, check} <-
           Check.prepare(
             action["check"],
             Map.get(state.actors[actor_id].skills, action["attribute"], 0)
           ) do
      {:ok, action |> Map.put("check", check) |> Map.merge(%{sources: [actor_id], variants: []})}
    end
  end

  defp resolve_terms(_state, _actor_id, _target, action),
    do: {:ok, Map.merge(action, %{sources: [], variants: []})}

  defp valid_terms?(terms),
    do:
      is_integer(terms["cost"]) and terms["cost"] in 0..1_000_000 and
        is_integer(terms["duration"]) and terms["duration"] in 0..31_536_000 and
        Scope.id?(terms["resource"])

  defp commit(state, actor_id, intent, inputs, terms, time) do
    actor = state.actors[actor_id]
    resources = Map.update(actor.resources, terms["resource"], 0, &(&1 - terms["cost"]))
    actor = %{actor | resources: resources, revision: actor.revision + 1}

    state = %{
      state
      | actors: Map.put(state.actors, actor_id, actor),
        time: time,
        revision: state.revision + 1,
        elapsed: state.elapsed + terms["duration"]
    }

    {state, result, audience} = transition(state, actor_id, intent, terms)

    effect = %{
      id: inputs.event_id,
      type: intent.type,
      actor_id: actor_id,
      target_id: intent.target_id,
      result: result,
      audience: audience,
      scope: state.scope,
      revision: state.revision,
      occurred_at: time.value,
      recorded_at: Map.get(inputs, :recorded_at),
      source_ids: terms.sources,
      variants: terms.variants,
      rules_ref: state.rules_ref,
      read_set: %{scope: state.scope, zone_id: state.zone_id, revision: state.revision - 1},
      resolution: Map.get(terms, :check_result),
      draws: inputs.draws
    }

    state = record_fact(state, actor_id, inputs.event_id, terms, effect)
    {:ok, %{state | events: state.events ++ [effect]}, [effect]}
  end

  defp transition(state, actor_id, intent, %{"kind" => "take"}) do
    item = %{state.items[intent.target_id] | owner: {:actor, actor_id}}
    audience = visible_audience(state, item.audience, state.actors[actor_id].audience)

    {%{state | items: Map.put(state.items, item.id, item)}, %{"quantity" => item.quantity},
     audience}
  end

  defp transition(state, actor_id, intent, %{"kind" => "drop"}) do
    item = %{state.items[intent.target_id] | owner: {:zone, state.zone_id}}
    audience = visible_audience(state, item.audience, state.actors[actor_id].audience)

    {%{state | items: Map.put(state.items, item.id, item)}, %{"quantity" => item.quantity},
     audience}
  end

  defp transition(state, actor_id, intent, terms) do
    audience =
      visible_audience(
        state,
        state.actors[intent.target_id].audience,
        state.actors[actor_id].audience
      )

    {state, %{"outcome" => Map.get(terms, "outcome", "completed"), "cost" => terms["cost"]},
     audience}
  end

  defp resolve_roll(_state, _actor_id, %{"kind" => "check"} = terms, draws) do
    with {:ok, result} <- Check.resolve(terms["check"], draws) do
      {:ok,
       terms
       |> Map.put("outcome", Atom.to_string(result.outcome))
       |> Map.put(:check_result, result)}
    end
  end

  defp resolve_roll(_state, _actor_id, terms, []), do: {:ok, terms}
  defp resolve_roll(_state, _actor_id, _terms, _draws), do: {:error, :unexpected_draws}

  defp visible_audience(state, first, second) do
    ids =
      state.actors
      |> Map.keys()
      |> Enum.filter(fn id ->
        Audience.permits?(first, %{actor_id: id}) and Audience.permits?(second, %{actor_id: id})
      end)

    Audience.freeze(:public, ids)
  end

  defp record_fact(state, actor_id, event_id, %{"kind" => "deed", "fact" => predicate}, effect) do
    fact = %Knowledge{
      id: event_id <> "/fact",
      kind: :fact,
      subject_id: actor_id,
      predicate: predicate,
      value: true,
      scope: state.scope,
      source_ids: [event_id],
      audience: effect.audience,
      occurred_at: effect.occurred_at,
      recorded_at: effect.recorded_at
    }

    %{state | knowledge: Map.put(state.knowledge, fact.id, fact)}
  end

  defp record_fact(state, _actor_id, _event_id, _terms, _effect), do: state
end
