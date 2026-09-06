defmodule Genesis.Core.Companions do
  @moduledoc "Voluntary, bounded following by existing NPCs. An invitation never grants control or inventory rights."
  alias Genesis.Core.{Audience, Knowledge, Scope, State}

  @spec handles?(type :: term()) :: boolean()
  def handles?(type), do: type in ~w(recruit agree dismiss)

  @spec valid?(actor :: map()) :: boolean()
  def valid?(actor), do: policy?(actor.companion_policy) and commitment?(actor)

  defp policy?(nil), do: true

  defp policy?(%{"version" => 1, "willing" => willing, "max_trips" => trips} = policy),
    do: map_size(policy) == 3 and is_boolean(willing) and is_integer(trips) and trips in 1..8

  defp policy?(_policy), do: false

  defp commitment?(%{commitment: nil}), do: true

  defp commitment?(%{kind: :npc, commitment: c, companion_of: leader}) when is_map(c) do
    Enum.sort(Map.keys(c)) == Enum.sort(~w(version status leader_id trips_left source_id)) and
      c["version"] == 1 and c["status"] in ~w(requested active refused dismissed completed) and
      Scope.id?(c["leader_id"]) and Scope.id?(c["source_id"]) and
      binding_valid?(c, leader)
  end

  defp commitment?(_actor), do: false

  defp binding_valid?(c, leader) do
    is_integer(c["trips_left"]) and c["trips_left"] in 0..8 and
      if(c["status"] == "active",
        do: leader == c["leader_id"] and c["trips_left"] > 0,
        else: is_nil(leader)
      )
  end

  @spec propose(state :: map(), actor :: String.t(), intent :: map(), id :: String.t()) :: term()
  def propose(state, actor, intent, id) do
    with {:ok, terms} <- terms(state, actor, intent) do
      {:ok,
       struct(Genesis.Core.Proposal,
         id: id,
         scope: state.scope,
         actor_id: actor,
         revision: state.revision,
         intent: intent,
         terms: terms,
         rules_ref: state.rules_ref
       )}
    end
  end

  @spec reduce(state :: map(), actor :: String.t(), intent :: map(), inputs :: map()) :: term()
  def reduce(state, actor, intent, inputs) do
    with {:ok, terms} <- terms(state, actor, intent),
         true <- inputs.draws == [] do
      npc = state.actors[intent.target_id]

      commitment = %{
        "version" => 1,
        "status" => terms["outcome"],
        "leader_id" => actor,
        "trips_left" => terms["trips"],
        "source_id" => inputs.event_id
      }

      npc = %{
        npc
        | companion_of: if(terms["outcome"] == "active", do: actor),
          commitment: commitment,
          revision: npc.revision + 1
      }

      event = %{
        id: inputs.event_id,
        type: intent.type,
        actor_id: actor,
        target_id: npc.id,
        result: %{"outcome" => terms["outcome"]},
        scope: state.scope,
        audience: {:actors, Enum.sort([actor, npc.id])},
        revision: state.revision + 1,
        occurred_at: state.time.value,
        recorded_at: Map.get(inputs, :recorded_at),
        source_ids: terms.sources,
        variants: [],
        rules_ref: state.rules_ref,
        read_set: %{scope: state.scope, zone_id: state.zone_id, revision: state.revision},
        draws: []
      }

      record =
        struct(Knowledge,
          id: inputs.event_id <> "/companionship",
          kind: :relationship,
          subject_id: npc.id,
          object_id: actor,
          predicate: "companionship",
          value: terms["outcome"],
          scope: state.scope,
          source_ids: [event.id],
          audience: event.audience,
          occurred_at: event.occurred_at,
          recorded_at: event.recorded_at
        )

      next = %{
        state
        | actors: Map.put(state.actors, npc.id, npc),
          knowledge: Map.put(state.knowledge, record.id, record),
          revision: event.revision,
          events: state.events ++ [event]
      }

      with {:ok, next} <- State.restore(next), do: {:ok, next, [event]}
    else
      false -> {:error, :unexpected_draws}
      error -> error
    end
  end

  defp terms(%{scope: %{kind: :published}}, _actor, _intent), do: {:error, :read_only_scope}
  defp terms(%{status: :paused}, _actor, _intent), do: {:error, :paused}

  defp terms(state, actor, %{type: type, target_id: target} = intent)
       when map_size(intent) == 2 do
    with true <- handles?(type),
         %{kind: :pc, alive: true, retired: false} <- state.actors[actor],
         %{kind: :npc} = npc <- state.actors[target],
         true <- Audience.permits?(npc.audience, %{actor_id: actor}),
         false <- anchored?(state, target),
         {:ok, outcome, trips} <- response(npc, actor, type) do
      sources = if npc.commitment, do: [npc.commitment["source_id"]], else: []

      {:ok,
       %{
         "outcome" => outcome,
         "trips" => trips,
         "cost" => 0,
         "duration" => 0,
         "summary" => "#{npc.name}: #{outcome} (up to #{trips} connected trips)",
         sources: sources
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :unavailable}
    end
  end

  defp terms(_state, _actor, _intent), do: {:error, :invalid_request}

  defp response(%{companion_of: actor}, actor, "dismiss"), do: {:ok, "dismissed", 0}
  defp response(%{alive: false}, _actor, _type), do: {:error, :unavailable}
  defp response(%{retired: true}, _actor, _type), do: {:error, :unavailable}

  defp response(%{companion_of: leader}, _actor, _type) when not is_nil(leader),
    do: {:error, :already_following}

  defp response(%{commitment: %{"status" => "requested"}}, _actor, "recruit"),
    do: {:error, :invitation_pending}

  defp response(npc, _actor, "recruit"),
    do: {:ok, "requested", (npc.companion_policy || %{})["max_trips"] || 1}

  defp response(
         %{commitment: %{"status" => "requested", "leader_id" => actor}} = npc,
         actor,
         "agree"
       ) do
    willing = (npc.companion_policy || %{})["willing"] == true

    {:ok, if(willing, do: "active", else: "refused"),
     if(willing, do: npc.commitment["trips_left"], else: 0)}
  end

  defp response(_npc, _actor, _type), do: {:error, :invitation_required}

  @spec anchored?(state :: map(), actor :: String.t()) :: boolean()
  def anchored?(state, actor),
    do:
      (not is_nil(state.settlement) and
         actor in [state.settlement["merchant_id"], state.settlement["representative_id"]]) or
        (not is_nil(state.timeline) and
           Enum.any?(state.timeline["schedules"], fn {_, row} -> row["actor_id"] == actor end))

  @spec party(state :: map(), leader :: String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def party(state, leader) do
    followers = state.actors |> Map.values() |> Enum.filter(&(&1.companion_of == leader))

    if length(followers) <= 7 and Enum.all?(followers, &traveler?/1),
      do: {:ok, [leader | Enum.sort(Enum.map(followers, & &1.id))]},
      else: {:error, :companion_unavailable}
  end

  defp traveler?(%{
         alive: true,
         retired: false,
         commitment: %{"status" => "active", "trips_left" => n}
       }),
       do: n > 0

  defp traveler?(_actor), do: false

  @spec arrive(actor :: map()) :: map()
  def arrive(%{companion_of: nil} = actor), do: actor

  def arrive(actor) do
    remaining = actor.commitment["trips_left"] - 1

    commitment =
      Map.merge(actor.commitment, %{
        "trips_left" => remaining,
        "status" => if(remaining == 0, do: "completed", else: "active")
      })

    %{
      actor
      | commitment: commitment,
        companion_of: if(remaining > 0, do: actor.companion_of),
        revision: actor.revision + 1
    }
  end
end
