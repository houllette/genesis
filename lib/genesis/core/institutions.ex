defmodule Genesis.Core.Institutions do
  @moduledoc "Voluntary affiliation, sourced obligations and local due process. Belief is neither canon nor platform authority."
  alias Genesis.Core.{Audience, Commerce, Context, Knowledge}

  @spec records(state :: map(), actor :: String.t(), representative :: String.t()) :: map()
  def records(state, actor, representative) do
    state.knowledge
    |> Map.values()
    |> Enum.filter(fn k ->
      k.scope == state.scope and k.subject_id == actor and k.object_id == representative and
        Audience.permits?(k.audience, %{actor_id: representative})
    end)
    |> Map.new(&{{&1.kind, &1.predicate}, &1})
  end

  @spec context(state :: map(), actor :: String.t(), representative :: String.t()) :: map()
  def context(state, actor, representative) do
    r = records(state, actor, representative)
    member = r[{:relationship, "local:member"}]
    obligation = r[{:obligation, "local:offering"}]
    debt = r[{:obligation, "local:restitution"}]

    eligible =
      match?(%{value: true}, member) and match?(%{value: "fulfilled"}, obligation) and
        is_nil(debt)

    %{
      eligible: eligible,
      sources: Enum.flat_map([member, obligation, debt], fn k -> if k, do: [k.id], else: [] end)
    }
  end

  @spec terms(state :: map(), actor :: String.t(), intent :: map()) ::
          {:ok, map()} | {:error, atom()}
  def terms(state, actor, %{type: "adjudicate", target_id: offender}),
    do: adjudicate(state, actor, offender)

  def terms(state, actor, %{target_id: representative} = intent) do
    if representative == state.settlement["representative_id"] and actor != representative,
      do: institution_terms(state, actor, representative, intent),
      else: {:error, :unavailable}
  end

  defp institution_terms(state, actor, representative, %{type: "affiliate"}) do
    cond do
      not state.settlement["accepting_members"] ->
        {:error, :institution_refused}

      records(state, actor, representative)[{:relationship, "local:member"}] ->
        {:error, :already_affiliated}

      true ->
        {:ok, base("Voluntarily affiliate; accept an obligation to offer supplies")}
    end
  end

  defp institution_terms(state, actor, representative, %{type: "offer", quantity: quantity}) do
    offering = state.local_rules["offering"]

    {:ok,
     base("Offer #{quantity} #{offering["commodity"]}; this does not purchase membership")
     |> Map.put("flows", [Commerce.flow(actor, representative, offering["commodity"], quantity)])}
  end

  defp institution_terms(state, actor, representative, %{type: "aid"}) do
    context = Context.institution(state, actor, representative)
    aid = state.local_rules["aid"]

    if context.eligible do
      {:ok,
       base("Redeem the fulfilled obligation for #{aid["quantity"]} #{aid["commodity"]}")
       |> Map.put("flows", [
         Commerce.flow(representative, actor, aid["commodity"], aid["quantity"])
       ])
       |> Map.put(:sources, context.sources)}
    else
      {:error, :aid_unavailable}
    end
  end

  defp institution_terms(_state, _actor, _representative, %{type: "trespass"}),
    do:
      {:ok,
       base("Enter the restricted store without permission; witnesses may report the violation")}

  defp institution_terms(state, actor, representative, %{type: "report", record_id: id}) do
    case state.knowledge[id] do
      %{kind: :fact, predicate: "local:trespass", object_id: ^representative, value: true} =
          record ->
        if record.scope == state.scope and Audience.permits?(record.audience, %{actor_id: actor}) do
          {:ok,
           base("Report a known violation to the responsible representative")
           |> Map.put(:sources, [id])}
        else
          {:error, :unavailable}
        end

      _ ->
        {:error, :unavailable}
    end
  end

  defp adjudicate(state, representative, offender) do
    observed = records(state, offender, representative)[{:observation, "local:trespass"}]
    debt = records(state, offender, representative)[{:obligation, "local:restitution"}]

    if (representative == state.settlement["representative_id"] and observed) && is_nil(debt) do
      {:ok,
       base("Record a restitution obligation and suspend this institution's aid")
       |> Map.put(:sources, [observed.id])}
    else
      {:error, :adjudication_unavailable}
    end
  end

  defp base(summary), do: %{"flows" => [], "summary" => summary, "duration" => 0}

  @spec apply(state :: map(), actor :: String.t(), intent :: map(), event :: map()) :: map()
  def apply(state, actor, %{type: "affiliate", target_id: representative}, event) do
    state
    |> record(event, "member", :relationship, actor, representative, "local:member", true)
    |> record(
      event,
      "obligation",
      :obligation,
      actor,
      representative,
      "local:offering",
      "pending"
    )
  end

  def apply(state, actor, %{type: "offer", target_id: representative, quantity: quantity}, event) do
    obligation = records(state, actor, representative)[{:obligation, "local:offering"}]

    if match?(%{value: "pending"}, obligation) and
         quantity >= state.local_rules["offering"]["quantity"],
       do: update_record(state, obligation, "fulfilled", event),
       else: state
  end

  def apply(state, actor, %{type: "aid", target_id: representative}, event),
    do:
      update_record(
        state,
        records(state, actor, representative)[{:obligation, "local:offering"}],
        "redeemed",
        event
      )

  def apply(state, actor, %{type: "trespass", target_id: representative}, event) do
    state =
      record(state, event, "violation", :fact, actor, representative, "local:trespass", true)

    if representative in elem(event.audience, 1),
      do:
        record(
          state,
          event,
          "observation",
          :observation,
          actor,
          representative,
          "local:trespass",
          true
        ),
      else: state
  end

  def apply(state, actor, %{type: "report", target_id: representative, record_id: id}, event) do
    original = state.knowledge[id]
    # An explicit report discloses this observation, not the private original event.
    event = %{
      event
      | audience: {:actors, Enum.uniq([actor, original.subject_id, representative])},
        source_ids: [id]
    }

    record(
      state,
      event,
      "observation",
      :observation,
      original.subject_id,
      representative,
      "local:trespass",
      true
    )
  end

  def apply(state, representative, %{type: "adjudicate", target_id: offender}, event) do
    state
    |> record(
      event,
      "restitution",
      :obligation,
      offender,
      representative,
      "local:restitution",
      "pending"
    )
    |> record(
      event,
      "standing",
      :relationship,
      offender,
      representative,
      "local:standing",
      "restricted"
    )
  end

  def apply(state, _actor, _intent, _event), do: state

  defp record(state, event, suffix, kind, actor, representative, predicate, value) do
    knowledge =
      struct(Knowledge,
        id: event.id <> "/" <> suffix,
        kind: kind,
        subject_id: actor,
        object_id: representative,
        predicate: predicate,
        value: value,
        scope: state.scope,
        source_ids: [event.id] ++ event.source_ids,
        audience: event.audience,
        occurred_at: event.occurred_at,
        learned_at: event.occurred_at,
        recorded_at: event.recorded_at
      )

    %{state | knowledge: Map.put(state.knowledge, knowledge.id, knowledge)}
  end

  defp update_record(state, record, value, event),
    do:
      put_in(state.knowledge[record.id], %{
        record
        | value: value,
          source_ids: Enum.uniq(record.source_ids ++ [event.id]),
          learned_at: event.occurred_at,
          recorded_at: event.recorded_at
      })
end
