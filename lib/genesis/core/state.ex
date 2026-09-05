defmodule Genesis.Core.State do
  @moduledoc "Pure zone state. Constructors validate trusted fixture/boundary values before reduction."
  alias Genesis.Core.Action
  alias Genesis.Core.Actor
  alias Genesis.Core.Audience
  alias Genesis.Core.Companions
  alias Genesis.Core.Context
  alias Genesis.Core.FictionalTime
  alias Genesis.Core.Item
  alias Genesis.Core.Knowledge
  alias Genesis.Core.Persona
  alias Genesis.Core.Scope
  alias Genesis.Core.Settlement

  @enforce_keys [:scope, :zone_id, :time]
  alias Genesis.Systems.LocalRules

  defstruct [
    :scope,
    :zone_id,
    :time,
    :rules_ref,
    :local_rules,
    :settlement,
    :actor_refs,
    name: nil,
    description: "",
    actors: %{},
    items: %{},
    knowledge: %{},
    actions: %{},
    context_rules: [],
    revision: 0,
    elapsed: 0,
    status: :active,
    events: []
  ]

  @type t :: %__MODULE__{
          scope: Genesis.Core.Scope.t(),
          zone_id: String.t(),
          time: Genesis.Core.FictionalTime.t(),
          rules_ref: term(),
          local_rules: map() | nil,
          settlement: map() | nil,
          actor_refs: [String.t()] | nil,
          name: String.t() | nil,
          description: String.t(),
          actors: map(),
          items: map(),
          knowledge: map(),
          actions: map(),
          context_rules: list(),
          revision: non_neg_integer(),
          elapsed: non_neg_integer(),
          status: :active | :paused,
          events: list()
        }

  @spec new(attrs :: map()) :: {:ok, t()} | {:error, atom()}
  def new(%{scope: scope, zone_id: zone, time: time} = attrs) do
    actors = Map.get(attrs, :actors, [])
    items = Map.get(attrs, :items, [])
    knowledge = Map.get(attrs, :knowledge, [])

    if valid_header?(attrs, scope, zone, time) and valid_collections?(actors, items, knowledge) and
         entities_valid?(attrs, actors, items, knowledge) and
         local?(attrs, actors, items) do
      {:ok,
       struct(
         __MODULE__,
         Map.merge(attrs, %{
           actors: index(Enum.map(actors, &materialize_actor/1)),
           items: index(items),
           knowledge: index(knowledge)
         })
       )}
    else
      {:error, :invalid_state}
    end
  end

  def new(_attrs), do: {:error, :invalid_state}

  defp entities_valid?(attrs, actors, items, knowledge) do
    Enum.all?(actors, &valid_actor?/1) and
      Enum.all?(items, &valid_item?(&1, actors, attrs.zone_id)) and
      references?(Map.get(attrs, :actor_refs), actors, knowledge) and
      Enum.all?(
        knowledge,
        &valid_knowledge?(&1, attrs.scope, actors, Map.get(attrs, :actor_refs) || [])
      ) and
      Enum.all?(actors, &valid_companion?(&1, actors))
  end

  @doc "Validates a decoded checkpoint without resetting its revisions or elapsed time."
  @spec restore(value :: term()) :: {:ok, t()} | {:error, :invalid_state}
  def restore(%__MODULE__{} = state) do
    with true <- valid_saved_header?(state),
         true <- Enum.all?([state.actors, state.items, state.knowledge], &valid_index?/1),
         true <-
           Enum.all?(state.actors, fn {_id, actor} ->
             match?(%Actor{}, actor) and revision?(actor.revision)
           end),
         attrs = state |> Map.from_struct() |> Map.drop([:revision, :elapsed, :status, :events]),
         attrs = Map.put(attrs, :actors, Enum.map(Map.values(state.actors), &%{&1 | revision: 0})),
         attrs = Map.put(attrs, :items, Map.values(state.items)),
         attrs = Map.put(attrs, :knowledge, Map.values(state.knowledge)),
         {:ok, _validated} <- new(attrs) do
      {:ok, state}
    else
      _ -> {:error, :invalid_state}
    end
  end

  def restore(_value), do: {:error, :invalid_state}

  defp valid_saved_header?(state),
    do:
      revision?(state.revision) and revision?(state.elapsed) and
        state.status in [:active, :paused] and is_list(state.events) and
        length(state.events) <= 2000 and
        Enum.all?(
          state.events,
          &(is_map(&1) and Scope.id?(Map.get(&1, :id)) and Map.get(&1, :scope) == state.scope)
        )

  defp revision?(value), do: is_integer(value) and value >= 0 and value <= 9_000_000_000_000

  defp valid_index?(values) when is_map(values),
    do: Enum.all?(values, fn {id, value} -> is_map(value) and Map.get(value, :id) == id end)

  defp valid_index?(_values), do: false

  @doc "Projects before delivery. Non-GM output excludes authoritative sources and private actor fields."
  @spec view(state :: t(), viewer :: map()) :: {:ok, map()} | {:error, :unavailable}
  def view(state, viewer) do
    if viewer[:role] in [:gm, :player, :spectator] and
         (viewer[:role] in [:gm, :spectator] or Map.has_key?(state.actors, viewer[:actor_id])) do
      actors =
        state.actors |> Map.values() |> Enum.filter(&Audience.permits?(&1.audience, viewer))

      actor_ids = Enum.map(actors, & &1.id)
      items = state.items |> Map.values() |> Enum.filter(&visible_item?(&1, viewer, actor_ids))

      knowledge =
        state.knowledge |> Map.values() |> Enum.filter(&visible_knowledge?(&1, viewer, actor_ids))

      {:ok,
       %{
         scope: state.scope,
         zone_id: state.zone_id,
         name: state.name || state.zone_id,
         description: state.description,
         time: state.time,
         elapsed: state.elapsed,
         revision: state.revision,
         status: state.status,
         settlement: Settlement.view(state, viewer),
         actors: actors |> Enum.map(&actor_view(&1, viewer)) |> Enum.sort_by(& &1.id),
         items: items |> Enum.map(&item_view(&1, viewer)) |> Enum.sort_by(& &1.id),
         knowledge: knowledge |> Enum.map(&knowledge_view(&1, viewer)) |> Enum.sort_by(& &1.id)
       }}
    else
      {:error, :unavailable}
    end
  end

  @spec inventory(state :: t(), actor_id :: String.t()) :: {:ok, list()} | {:error, :unavailable}
  def inventory(state, actor_id) do
    with {:ok, view} <- view(state, %{role: :player, actor_id: actor_id}) do
      {:ok, Enum.filter(view.items, &(&1.owner == {:actor, actor_id}))}
    end
  end

  @spec pause(state :: t()) :: t()
  def pause(%{status: :paused} = state), do: state
  def pause(state), do: %{state | status: :paused, revision: state.revision + 1}

  @spec resume(state :: t()) :: t()
  def resume(%{status: :active} = state), do: state
  def resume(state), do: %{state | status: :active, revision: state.revision + 1}

  defp valid_header?(attrs, scope, zone, time) do
    allowed = [
      :scope,
      :zone_id,
      :time,
      :rules_ref,
      :local_rules,
      :settlement,
      :actor_refs,
      :name,
      :description,
      :actors,
      :items,
      :knowledge,
      :actions,
      :context_rules
    ]

    Enum.all?(Map.keys(attrs), &(&1 in allowed)) and Scope.valid?(scope) and Scope.id?(zone) and
      FictionalTime.valid?(time) and time.world_id == scope.world_id and
      rules?(attrs) and zone_metadata?(attrs)
  end

  defp zone_metadata?(attrs) do
    name = Map.get(attrs, :name)
    description = Map.get(attrs, :description, "")

    (is_nil(name) or Scope.id?(name)) and is_binary(description) and
      byte_size(description) <= 4000 and String.valid?(description)
  end

  defp rules?(attrs),
    do:
      Action.valid_set?(Map.get(attrs, :actions, %{})) and
        Context.valid?(Map.get(attrs, :context_rules, [])) and
        rules_ref?(Map.get(attrs, :rules_ref))

  defp rules_ref?(nil), do: true
  defp rules_ref?({id, version}), do: Scope.id?(id) and is_integer(version) and version > 0

  defp rules_ref?(%{"id" => id, "version" => version, "format" => 1, "digest" => digest} = ref),
    do:
      map_size(ref) == 4 and Scope.id?(id) and is_integer(version) and version > 0 and
        is_binary(digest) and byte_size(digest) == 64

  defp rules_ref?(_ref), do: false

  defp unique?(values) when is_list(values) and length(values) <= 500 do
    Enum.all?(values, &(is_map(&1) and Scope.id?(Map.get(&1, :id)))) and
      length(Enum.uniq_by(values, & &1.id)) == length(values)
  end

  defp unique?(_values), do: false
  defp index(values), do: Map.new(values, &{&1.id, &1})

  defp valid_actor?(%Actor{} = actor) do
    Scope.id?(actor.name) and actor.kind in [:pc, :npc] and actor.revision == 0 and
      is_boolean(actor.alive) and is_boolean(actor.retired) and Audience.valid?(actor.audience) and
      valid_traits?(actor.traits) and numeric_map?(actor.skills) and
      actor_details?(actor)
  end

  defp valid_actor?(_actor), do: false

  defp actor_details?(actor),
    do:
      numeric_map?(actor.resources) and Persona.valid?(actor.persona) and Companions.valid?(actor)

  defp materialize_actor(%Actor{kind: :npc} = actor),
    do: %{actor | persona: Persona.materialize(actor.id, actor.persona)}

  defp materialize_actor(actor), do: actor

  defp valid_traits?(traits) when is_list(traits) and length(traits) <= 32,
    do: Enum.all?(traits, &Scope.id?/1) and Enum.uniq(traits) == traits

  defp valid_traits?(_traits), do: false

  defp numeric_map?(values) when is_map(values) and map_size(values) <= 32 do
    Enum.all?(values, fn {key, value} ->
      Scope.id?(key) and is_integer(value) and value in 0..1_000_000
    end)
  end

  defp numeric_map?(_values), do: false

  defp valid_item?(%Item{} = item, actors, zone) do
    Scope.id?(item.name) and is_integer(item.quantity) and quantity?(item) and
      Audience.valid?(item.audience) and valid_owner?(item.owner, actors, zone)
  end

  defp valid_item?(_item, _actors, _zone), do: false
  defp quantity?(%{commodity: nil, quantity: quantity}), do: quantity in 1..1_000_000

  defp quantity?(%{commodity: commodity, quantity: quantity}),
    do: Scope.id?(commodity) and quantity in 0..1_000_000

  defp local?(attrs, actors, items) do
    rules = Map.get(attrs, :local_rules)
    settlement = Map.get(attrs, :settlement)
    state = Map.merge(attrs, %{actors: index(actors), local_rules: rules})

    (is_nil(rules) or LocalRules.valid?(rules)) and
      Settlement.valid?(settlement, state) and
      Enum.all?(items, &local_item?(&1, rules, settlement)) and balances_bounded?(items)
  end

  defp local_item?(%{commodity: nil}, _rules, _settlement), do: true
  defp local_item?(_item, nil, _settlement), do: false

  defp local_item?(item, rules, _settlement) do
    # A market controls exchange and issuance, not whether a traveler can carry
    # a ruleset-defined commodity through a place without a market.
    Map.has_key?(rules["commodities"], item.commodity) and
      item.name == rules["commodities"][item.commodity] and
      match?({:actor, _id}, item.owner)
  end

  defp balances_bounded?(items) do
    items
    |> Enum.reject(&is_nil(&1.commodity))
    |> Enum.group_by(&{&1.owner, &1.commodity})
    |> Enum.all?(fn {_key, lots} -> Enum.sum(Enum.map(lots, & &1.quantity)) <= 1_000_000 end)
  end

  defp valid_owner?({:zone, zone}, _actors, zone), do: true
  defp valid_owner?({:actor, id}, actors, _zone), do: Enum.any?(actors, &(&1.id == id))
  defp valid_owner?(_owner, _actors, _zone), do: false
  defp valid_companion?(%{companion_of: nil}, _actors), do: true

  defp valid_companion?(%{kind: :npc, id: id, companion_of: target}, actors),
    do: target != id and Enum.any?(actors, &(&1.id == target and &1.kind == :pc))

  defp valid_companion?(_actor, _actors), do: false

  defp valid_knowledge?(%Knowledge{} = record, scope, actors, refs) do
    record.kind in Knowledge.kinds() and record.scope == scope and record.version == 1 and
      Scope.id?(record.predicate) and scalar?(record.value) and Audience.valid?(record.audience) and
      knowledge_owners?(record, actors, refs) and provenance?(record)
  end

  defp valid_knowledge?(_record, _scope, _actors, _refs), do: false

  defp knowledge_owners?(record, actors, refs),
    do:
      Enum.any?(actors, &(&1.id == record.subject_id)) and
        (is_nil(record.object_id) or record.object_id in refs or
           Enum.any?(actors, &(&1.id == record.object_id)))

  # References carry identity only, never inventory, presence, skills or authority.
  # The shell validates their existence and claims across the whole footprint.
  defp references?(refs, actors, knowledge) do
    ids = Enum.map(actors, & &1.id)

    required =
      knowledge
      |> Enum.map(&Map.get(&1, :object_id))
      |> Enum.reject(&(&1 == nil or &1 in ids))
      |> Enum.uniq()
      |> Enum.sort()

    refs = if is_nil(refs), do: [], else: refs
    is_list(refs) and length(refs) <= 500 and Enum.all?(refs, &Scope.id?/1) and refs == required
  end

  defp provenance?(record),
    do:
      valid_sources?(record.source_ids) and is_integer(record.occurred_at) and
        learned_time?(record.learned_at, record.occurred_at) and
        recording_time?(record.recorded_at)

  defp valid_sources?(ids) when is_list(ids) and length(ids) in 1..32,
    do: Enum.all?(ids, &Scope.id?/1)

  defp valid_sources?(_ids), do: false
  defp learned_time?(nil, _occurred), do: true
  defp learned_time?(learned, occurred), do: is_integer(learned) and learned >= occurred
  defp recording_time?(nil), do: true
  defp recording_time?(%DateTime{time_zone: "Etc/UTC", utc_offset: 0, std_offset: 0}), do: true
  defp recording_time?(_time), do: false
  defp scalar?(value) when is_boolean(value), do: true
  defp scalar?(value) when is_integer(value), do: abs(value) <= 1_000_000
  defp scalar?(value) when is_binary(value), do: byte_size(value) <= 2048 and String.valid?(value)
  defp scalar?(_value), do: false

  defp valid_collections?(actors, items, knowledge),
    do:
      unique?(actors) and unique?(items) and
        unique?(knowledge) and unique?(actors ++ items ++ knowledge)

  defp visible_item?(item, viewer, actor_ids) do
    owner_visible =
      case item.owner do
        {:actor, id} -> id in actor_ids
        {:zone, _id} -> true
      end

    owner_visible and Audience.permits?(item.audience, viewer)
  end

  defp visible_knowledge?(record, viewer, actor_ids),
    do:
      Audience.permits?(record.audience, viewer) and record.subject_id in actor_ids and
        (is_nil(record.object_id) or record.object_id in actor_ids or viewer[:role] == :gm)

  defp actor_view(actor, %{role: :gm}), do: Map.from_struct(actor)

  defp actor_view(%{id: id} = actor, %{actor_id: id}),
    do: Map.take(actor, [:id, :name, :kind, :traits, :skills, :resources, :alive, :retired])

  defp actor_view(actor, _viewer), do: Map.take(actor, [:id, :name, :kind, :alive])
  defp item_view(item, %{role: :gm}), do: Map.from_struct(item)
  defp item_view(item, _viewer), do: Map.take(item, [:id, :name, :owner, :quantity, :commodity])
  defp knowledge_view(record, %{role: :gm}), do: Map.from_struct(record)

  defp knowledge_view(record, _viewer),
    do:
      Map.take(record, [
        :id,
        :kind,
        :subject_id,
        :object_id,
        :predicate,
        :value,
        :occurred_at,
        :learned_at
      ])
end
