defmodule Genesis.Persistence.Snapshots do
  @moduledoc "Validated current snapshots and immutable historical checkpoints. Called by authority transactions."
  import Ecto.Query
  alias Genesis.Core.{Scope, State}
  alias Genesis.Persistence.{Checkpoint, Codec, Entity, Snapshot, Tx, World}
  alias Genesis.Repo
  alias Genesis.Systems

  @spec key(scope :: Scope.t()) :: String.t()
  def key(scope), do: Codec.digest(Scope.key(scope))

  @spec find(world_id :: String.t(), scope :: Scope.t(), zone_id :: String.t()) ::
          Snapshot.t() | nil
  def find(world_id, scope, zone),
    do: Repo.get_by(Snapshot, world_id: world_id, scope_key: key(scope), zone_id: zone)

  @spec load(snapshot :: Snapshot.t()) :: {:ok, State.t()} | {:error, atom()}
  def load(snapshot) do
    with {:ok, state} <- Codec.load_state(snapshot.state),
         true <- Codec.digest(state) == snapshot.digest and state.revision == snapshot.revision,
         true <- stored_identity?(snapshot, state),
         true <-
           state.scope.world_id == snapshot.world_id and key(state.scope) == snapshot.scope_key,
         %World{} = world <- Repo.get(World, snapshot.world_id),
         :ok <- compatible(world, state) do
      {:ok, state}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :corrupt_snapshot}
    end
  end

  defp stored_identity?(snapshot, state),
    do:
      state.zone_id == snapshot.zone_id and state.scope.generation == snapshot.generation and
        Atom.to_string(state.scope.kind) == snapshot.scope_kind and
        state.scope.id == snapshot.experience_id

  @spec compatible(world :: World.t(), state :: State.t()) :: :ok | {:error, atom()}
  def compatible(world, state) do
    with {:ok, bundle} <- Systems.Bundle.validate(world.bundle),
         true <- state.rules_ref == bundle.ref,
         rules = Systems.scene_rules(bundle),
         true <- state.actions == rules.actions and state.context_rules == rules.context_rules,
         true <- state.local_rules == Map.get(rules, :local_rules),
         true <- references_exist?(world.id, state.actor_refs || []),
         true <- state.scope.world_id == world.id and state.scope.generation == world.generation,
         true <-
           state.time.world_id == world.id and state.time.calendar_id == world.calendar_id and
             state.time.calendar_version == world.calendar_version do
      :ok
    else
      _ -> {:error, :incompatible_snapshot}
    end
  end

  defp references_exist?(_world, []), do: true

  defp references_exist?(world, ids),
    do:
      Repo.aggregate(
        from(e in Entity,
          where: e.world_id == ^world and e.kind == "actor" and e.entity_id in ^ids
        ),
        :count
      ) == length(ids)

  @spec create!(
          world :: World.t(),
          state :: State.t(),
          experience_id :: String.t() | nil,
          base_checkpoint :: String.t() | nil
        ) ::
          Snapshot.t()
  def create!(world, state, experience_id \\ nil, base_checkpoint \\ nil) do
    snapshot =
      Tx.insert!(Snapshot, %{
        world_id: world.id,
        generation: state.scope.generation,
        scope_key: key(state.scope),
        scope_kind: Atom.to_string(state.scope.kind),
        experience_id: experience_id,
        base_checkpoint_id: base_checkpoint,
        zone_id: state.zone_id,
        revision: state.revision,
        state: Codec.dump!(state),
        digest: Codec.digest(state)
      })

    if state.scope.kind == :published, do: index!(state)
    snapshot
  end

  @spec save!(snapshot :: Snapshot.t(), state :: State.t()) :: Snapshot.t()
  def save!(snapshot, state) do
    if state.scope.kind == :published, do: index!(state)

    Tx.update!(snapshot, %{
      state: Codec.dump!(state),
      revision: state.revision,
      digest: Codec.digest(state)
    })
  end

  @spec checkpoint!(snapshot :: Snapshot.t(), cursor :: non_neg_integer()) :: Checkpoint.t()
  def checkpoint!(snapshot, cursor),
    do:
      Tx.insert!(Checkpoint, %{
        world_id: snapshot.world_id,
        snapshot_id: snapshot.id,
        cursor: cursor,
        state: snapshot.state,
        digest: snapshot.digest
      })

  @spec index!(state :: State.t()) :: :ok
  def index!(state) do
    Enum.each(entities(state), fn attrs ->
      attrs = Map.put(attrs, :world_id, state.scope.world_id)

      case Repo.get_by(Entity,
             world_id: attrs.world_id,
             kind: attrs.kind,
             entity_id: attrs.entity_id
           ) do
        nil -> Tx.insert!(Entity, attrs)
        %{zone_id: zone} = existing when zone == state.zone_id -> Tx.update!(existing, attrs)
        _ -> Repo.rollback(:owned_elsewhere)
      end
    end)

    :ok
  end

  @doc "Checks the complete published ownership index before admitting a batch publication."
  @spec check_index(states :: [State.t()]) :: :ok | {:error, atom()}
  def check_index([first | _] = states) do
    zones = Enum.map(states, & &1.zone_id)
    fields = [:kind, :entity_id, :zone_id, :owner_kind, :owner_id, :actor_kind]

    expected =
      Enum.flat_map(states, &entities/1)
      |> Enum.map(&Map.new(fields, fn f -> {f, Map.get(&1, f)} end))

    actual =
      Repo.all(
        from e in Entity, where: e.world_id == ^first.scope.world_id and e.zone_id in ^zones
      )
      |> Enum.map(&Map.take(&1, fields))

    if Enum.sort(expected) == Enum.sort(actual), do: :ok, else: {:error, :stale_ownership}
  end

  @doc "Relocates existing index rows atomically; callers have validated conservation and hold the World lock."
  @spec reindex!(before :: [State.t()], candidates :: [State.t()]) :: :ok
  def reindex!(before, candidates) do
    case check_index(before) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end

    [first | _] = before
    zones = Enum.map(before, & &1.zone_id)

    for state <- candidates, attrs <- entities(state) do
      attrs = Map.put(attrs, :world_id, first.scope.world_id)

      relocate_index!(attrs, zones)
    end

    :ok
  end

  defp relocate_index!(attrs, zones) do
    case Repo.get_by(Entity,
           world_id: attrs.world_id,
           kind: attrs.kind,
           entity_id: attrs.entity_id
         ) do
      nil ->
        Tx.insert!(Entity, attrs)

      existing ->
        if existing.zone_id in zones,
          do: Tx.update!(existing, attrs),
          else: Repo.rollback(:owned_elsewhere)
    end
  end

  defp entities(state) do
    [%{kind: "zone", entity_id: state.zone_id, zone_id: state.zone_id}] ++
      Enum.map(state.actors, fn {id, actor} ->
        %{
          kind: "actor",
          entity_id: id,
          zone_id: state.zone_id,
          actor_kind: Atom.to_string(actor.kind)
        }
      end) ++
      Enum.map(state.items, fn {id, item} ->
        {kind, owner} = item.owner

        %{
          kind: "item",
          entity_id: id,
          zone_id: state.zone_id,
          owner_kind: Atom.to_string(kind),
          owner_id: owner
        }
      end)
  end

  @spec published(world :: World.t()) :: [Snapshot.t()]
  def published(world),
    do:
      Repo.all(
        from s in Snapshot,
          where:
            s.world_id == ^world.id and s.generation == ^world.generation and
              s.scope_kind == "published",
          order_by: s.zone_id
      )
end
