defmodule Genesis.Core.Transfer do
  @moduledoc "Atomic bounded party movement. Knowledge follows its subject; remote objects are identity-only references."
  alias Genesis.Core.Companions
  alias Genesis.Core.Scene
  alias Genesis.Core.Scope
  alias Genesis.Core.State

  @spec valid_exchange?(exchange :: term()) :: boolean()
  def valid_exchange?(nil), do: true

  def valid_exchange?(%{"type" => type, "target_id" => target, "quantity" => n} = exchange),
    do:
      map_size(exchange) == 3 and type in ~w(buy sell barter offer) and
        Scope.id?(target) and is_integer(n) and n in 1..100

  def valid_exchange?(_exchange), do: false

  @doc "A delivery is a real party journey followed by one declared local exchange, committed as one operation."
  @spec execute(
          source :: map(),
          destination :: map(),
          actor :: String.t(),
          exchange :: term(),
          id :: String.t()
        ) :: term()
  def execute(source, destination, actor, exchange, id) do
    with true <- valid_exchange?(exchange),
         {:ok, left, right} <- move(source, destination, actor),
         {:ok, right} <- exchange(right, actor, exchange, id) do
      {:ok, left, right}
    else
      false -> {:error, :invalid_exchange}
      error -> error
    end
  end

  defp exchange(state, _actor, nil, _id), do: {:ok, state}

  defp exchange(state, actor, exchange, id) do
    intent = %{
      type: exchange["type"],
      target_id: exchange["target_id"],
      quantity: exchange["quantity"]
    }

    inputs = %{
      scope: state.scope,
      expected_revision: state.revision,
      event_id: id <> "/exchange",
      draws: []
    }

    with {:ok, next, [event]} <- Scene.reduce(state, actor, intent, inputs),
         true <- next.elapsed == state.elapsed do
      event = %{event | revision: state.revision}
      # The intermediate arrival is never acknowledged or persisted separately.
      {:ok, %{next | revision: state.revision, events: state.events ++ [event]}}
    else
      false -> {:error, :time_reconciliation_unavailable}
      error -> error
    end
  end

  @spec move(source :: map(), destination :: map(), actor :: String.t()) :: term()
  def move(source, destination, actor) do
    with {:ok, _} <- State.restore(source),
         {:ok, _} <- State.restore(destination),
         :ok <- compatible(source, destination),
         %{alive: true, retired: false, companion_of: nil} <- source.actors[actor],
         false <- Map.has_key?(destination.actors, actor),
         {:ok, party} <- Companions.party(source, actor),
         :ok <- movable(source, party) do
      items =
        Map.filter(source.items, fn
          {_id, %{owner: {:actor, owner}}} -> owner in party
          _ -> false
        end)

      knowledge = Map.filter(source.knowledge, fn {_id, k} -> k.subject_id in party end)

      actors =
        source.actors |> Map.take(party) |> Map.new(fn {id, a} -> {id, Companions.arrive(a)} end)

      arriving = %{actors: actors, items: items, knowledge: knowledge}

      if disjoint?(arriving, destination) do
        left = %{
          source
          | actors: Map.drop(source.actors, party),
            items: Map.drop(source.items, Map.keys(items)),
            knowledge: Map.drop(source.knowledge, Map.keys(knowledge)),
            revision: source.revision + 1
        }

        right = %{
          destination
          | actors: Map.merge(destination.actors, arriving.actors),
            items: Map.merge(destination.items, items),
            knowledge: Map.merge(destination.knowledge, knowledge),
            revision: destination.revision + 1
        }

        validate_pair(references(left), references(right))
      else
        {:error, :identity_collision}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unavailable}
    end
  end

  defp validate_pair(left, right) do
    with {:ok, _} <- State.restore(left),
         {:ok, _} <- State.restore(right),
         do: {:ok, left, right}
  end

  defp compatible(a, b) do
    cond do
      not same_experience?(a, b) ->
        {:error, :invalid_scope}

      not same_time?(a, b) ->
        {:error, :time_reconciliation_unavailable}

      a.status != :active or b.status != :active ->
        {:error, :paused}

      a.rules_ref != b.rules_ref or a.local_rules != b.local_rules ->
        {:error, :incompatible_rules}

      true ->
        :ok
    end
  end

  defp same_experience?(a, b),
    do: a.scope == b.scope and a.scope.kind == :experience and a.zone_id != b.zone_id

  defp same_time?(a, b), do: a.elapsed == 0 and b.elapsed == 0 and a.time == b.time

  defp movable(state, party),
    do:
      if(Enum.any?(party, &Companions.anchored?(state, &1)),
        do: {:error, :cross_zone_dependency},
        else: :ok
      )

  @spec references(state :: map()) :: map()
  def references(state) do
    refs =
      state.knowledge
      |> Map.values()
      |> Enum.map(& &1.object_id)
      |> Enum.reject(&(is_nil(&1) or Map.has_key?(state.actors, &1)))
      |> Enum.uniq()
      |> Enum.sort()

    %{state | actor_refs: if(refs == [], do: nil, else: refs)}
  end

  defp disjoint?(arriving, destination) do
    ids = Enum.flat_map([:actors, :items, :knowledge], &Map.keys(Map.fetch!(arriving, &1)))
    present = Enum.flat_map([:actors, :items, :knowledge], &Map.keys(Map.fetch!(destination, &1)))
    Enum.all?(ids, &(&1 not in present))
  end
end
