defmodule Genesis.Core.LocalAction do
  @moduledoc "Settlement actions behind the same proposal, Zone, receipt and replay protocol as scene actions."
  alias Genesis.Core.{
    Audience,
    Commerce,
    Economy,
    FictionalTime,
    Institutions,
    Proposal,
    Scope,
    State,
    Stock
  }

  @quantities ~w(buy sell barter produce offer disrupt)
  @simple ~w(rest affiliate aid trespass adjudicate)

  @spec handles?(type :: term()) :: boolean()
  def handles?(type), do: type in (@quantities ++ @simple ++ ["report"])

  @spec valid_intent?(intent :: term()) :: boolean()
  def valid_intent?(%{type: type, target_id: target, quantity: quantity} = intent)
      when type in @quantities,
      do:
        map_size(intent) == 3 and Scope.id?(target) and is_integer(quantity) and
          quantity in 1..100

  def valid_intent?(%{type: type, target_id: target} = intent) when type in @simple,
    do: map_size(intent) == 2 and Scope.id?(target)

  def valid_intent?(%{type: "report", target_id: target, record_id: record} = intent),
    do: map_size(intent) == 3 and Scope.id?(target) and Scope.id?(record)

  def valid_intent?(_intent), do: false

  @spec propose(state :: State.t(), actor :: String.t(), intent :: map(), id :: String.t()) ::
          {:ok, Proposal.t()} | {:error, atom()}
  def propose(state, actor, intent, id) do
    with true <- Scope.id?(id),
         :ok <- available(state, actor, intent),
         {:ok, terms} <- terms(state, actor, intent),
         {:ok, _, _} <- Stock.flows(state, terms["flows"], "preview-" <> id) do
      terms =
        terms
        |> Map.put("basis", basis(state))
        |> Map.put("expires_at", state.time.value + state.settlement["quote_ttl"])

      {:ok,
       struct(Proposal,
         id: id,
         scope: state.scope,
         actor_id: actor,
         revision: state.revision,
         intent: intent,
         terms: terms,
         rules_ref: state.rules_ref
       )}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_proposal}
    end
  end

  @spec revalidate(state :: State.t(), proposal :: Proposal.t()) :: :ok | {:error, atom()}
  def revalidate(state, proposal) do
    cond do
      proposal.scope != state.scope or proposal.rules_ref != state.rules_ref ->
        {:error, :stale_proposal}

      state.time.value >= proposal.terms["expires_at"] ->
        {:error, :quote_expired}

      true ->
        with {:ok, current} <- propose(state, proposal.actor_id, proposal.intent, proposal.id),
             true <-
               Map.delete(current.terms, "expires_at") == Map.delete(proposal.terms, "expires_at") do
          :ok
        else
          _ -> {:error, :stale_proposal}
        end
    end
  end

  @spec reduce(state :: State.t(), actor :: String.t(), intent :: map(), inputs :: map()) ::
          {:ok, State.t(), [map()]} | {:error, atom()}
  def reduce(state, actor, intent, inputs) do
    execute(state, actor, intent, inputs, false)
  end

  @doc "Resolve an explicitly authorized NPC routine at its due point, without adding its duration again."
  @spec scheduled(state :: State.t(), actor :: String.t(), intent :: map(), inputs :: map()) ::
          term()
  def scheduled(state, actor, intent, inputs), do: execute(state, actor, intent, inputs, true)

  defp execute(state, actor, intent, inputs, scheduled?) do
    with :ok <- available(state, actor, intent),
         true <- inputs.draws == [],
         {:ok, terms} <- terms(state, actor, intent),
         terms = if(scheduled?, do: Map.put(terms, "duration", 0), else: terms),
         {:ok, time} <-
           FictionalTime.advance(state.time, %{unit: :second, value: terms["duration"]}),
         {:ok, changed, flows} <- Stock.flows(state, terms["flows"], inputs.event_id) do
      event = %{
        id: inputs.event_id,
        type: intent.type,
        actor_id: actor,
        target_id: intent.target_id,
        result: %{"outcome" => terms["summary"]},
        scope: state.scope,
        audience: audience(state, actor, intent),
        revision: state.revision + 1,
        occurred_at: time.value,
        recorded_at: Map.get(inputs, :recorded_at),
        source_ids: Map.get(terms, :sources, []),
        variants: [],
        rules_ref: state.rules_ref,
        read_set: %{scope: state.scope, zone_id: state.zone_id, revision: state.revision},
        draws: [],
        accounting: %{
          "version" => 1,
          "kind" => Map.get(terms, "accounting_kind", "transfer"),
          "flows" => flows,
          "recipe" => Map.get(terms, "recipe"),
          "policy" => state.settlement["profile"]
        }
      }

      changed = changed |> Economy.apply(actor, terms) |> Institutions.apply(actor, intent, event)
      changed = update_in(changed.actors[actor].revision, &(&1 + 1))

      next = %{
        changed
        | time: time,
          elapsed: state.elapsed + terms["duration"],
          revision: event.revision,
          events: state.events ++ [event]
      }

      with {:ok, next} <- State.restore(next), do: {:ok, next, [event]}
    else
      false -> {:error, :unexpected_draws}
      error -> error
    end
  end

  defp available(%{scope: %{kind: :published}}, _actor, _intent), do: {:error, :read_only_scope}
  defp available(%{status: :paused}, _actor, _intent), do: {:error, :paused}
  defp available(%{settlement: nil}, _actor, _intent), do: {:error, :unsupported_capability}

  defp available(state, actor, intent) do
    cond do
      not state.settlement["enabled"] -> {:error, :unsupported_capability}
      not valid_intent?(intent) -> {:error, :invalid_request}
      not match?(%{alive: true, retired: false}, state.actors[actor]) -> {:error, :unavailable}
      not target_visible?(state, actor, intent) -> {:error, :unavailable}
      true -> :ok
    end
  end

  defp target_visible?(_state, _actor, %{type: "produce"}), do: true

  defp target_visible?(state, actor, %{target_id: target}) do
    case state.actors[target] do
      %{alive: true, retired: false} = target ->
        Audience.permits?(target.audience, %{actor_id: actor})

      _ ->
        false
    end
  end

  defp terms(state, actor, %{type: type} = intent) when type in ~w(buy sell barter),
    do: Commerce.terms(state, actor, intent)

  defp terms(state, actor, %{type: type} = intent) when type in ~w(produce rest disrupt),
    do: Economy.terms(state, actor, intent)

  defp terms(state, actor, intent), do: Institutions.terms(state, actor, intent)

  defp audience(state, actor, %{type: "trespass", target_id: target}) do
    witnessed =
      state.settlement["witnessing"] and
        Audience.permits?(state.actors[actor].audience, %{actor_id: target})

    {:actors, if(witnessed, do: Enum.sort([actor, target]), else: [actor])}
  end

  defp audience(_state, actor, %{type: type}) when type in ~w(produce rest),
    do: {:actors, [actor]}

  defp audience(_state, actor, %{target_id: target}),
    do: {:actors, Enum.sort(Enum.uniq([actor, target]))}

  # Strict consulted-state binding excludes lifecycle-only revision changes and
  # wall time. Pause/resume does not expire or alter an otherwise unchanged quote.
  defp basis(state),
    do:
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(
          {state.actors, state.items, state.knowledge, state.settlement, state.local_rules}
        )
      )
      |> Base.encode16(case: :lower)
end
