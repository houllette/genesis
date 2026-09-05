defmodule Genesis.Persistence.Curation do
  @moduledoc "Published authoring below World/Zone ownership. An open window redirects edits to explicit drafts."
  import Ecto.Query
  alias Genesis.Core.Curation, as: Reducer
  alias Genesis.Core.{FictionalTime, Scope, State}
  alias Genesis.Persistence.{Access, Codec, Draft, Snapshot, Snapshots, Transition, Tx, Window}
  alias Genesis.{Repo, Systems, Worlds}

  @spec create_zone(
          scope :: term(),
          world_id :: String.t(),
          attrs :: map(),
          request :: String.t()
        ) ::
          {:ok, map()} | {:error, term()}
  def create_zone(scope, world_id, attrs, request) do
    Tx.run(world_id, fn world ->
      with :ok <- Access.world(scope, world_id, ["steward", "builder"]),
           {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(request),
           {:ok, scene} <- empty_scene(world, Worlds.named_id([world_id, user, request]), attrs) do
        create_or_restore(world, user, scene, attrs, request)
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_record}
      end
    end)
  end

  defp create_or_restore(world, user, scene, attrs, request) do
    payload = {"zone", attrs}

    case Tx.receipt(world.id, "authoring", user, request, payload) do
      :new ->
        result =
          if window_open?(world.id),
            do: draft!(world, user, scene.zone_id, scene.zone_id, attrs),
            else: create!(world, user, scene)

        Tx.remember!(world.id, "authoring", user, request, payload, result)
        {:ok, result}

      result ->
        result
    end
  end

  @spec edit(scope :: term(), snapshot_id :: String.t(), before :: State.t(), operation :: map()) ::
          {:ok, map()} | {:error, term()}
  def edit(scope, snapshot_id, before, operation) do
    Tx.run(before.scope.world_id, fn world ->
      with :ok <- Access.world(scope, world.id, ["steward", "builder"]),
           {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(operation.request) and before.scope.kind == :published do
        edit_or_restore(world, user, Repo.get!(Snapshot, snapshot_id), before, operation)
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_record}
      end
    end)
  end

  defp edit_or_restore(world, user, snapshot, before, op) do
    payload = {before.zone_id, op.revision, op.id, op.attrs}

    case Tx.receipt(world.id, "authoring", user, op.request, payload) do
      :new -> edit_new(world, user, snapshot, before, op, payload)
      {:ok, result} -> {:ok, %{scene: before, result: result}}
      error -> error
    end
  end

  defp edit_new(world, user, snapshot, before, op, payload) do
    id = op.id || Worlds.named_id([world.id, user, op.request])

    with true <- before.revision == op.revision and snapshot.digest == Codec.digest(before),
         :ok <- existing_reference(before, op.id, op.attrs),
         {:ok, character} <- character(world, id, op.attrs),
         {:ok, next} <- Reducer.apply(before, id, op.attrs, character) do
      {scene, result} = save_edit(world, user, snapshot, before, next, id, op.attrs)
      Tx.remember!(world.id, "authoring", user, op.request, payload, result)
      {:ok, %{scene: scene, result: result}}
    else
      false -> {:error, :stale_revision}
      {:error, _reason} = error -> error
    end
  end

  defp save_edit(world, user, snapshot, before, next, id, attrs) do
    if window_open?(world.id) do
      {before, draft!(world, user, before.zone_id, id, attrs)}
    else
      {:ok, transition} = Transition.between(before, next)
      snapshot = Snapshots.save!(snapshot, next)
      event = record!(world, user, snapshot, "record_curated", transition)
      Snapshots.checkpoint!(snapshot, event.cursor)
      {next, %{"status" => "published", "entity_id" => id, "zone_id" => next.zone_id}}
    end
  end

  defp existing_reference(_state, nil, _attrs), do: :ok
  defp existing_reference(state, id, %{"kind" => "zone"}) when id == state.zone_id, do: :ok

  defp existing_reference(state, id, %{"kind" => kind}) when kind in ["npc", "pc"] do
    if Map.has_key?(state.actors, id), do: :ok, else: {:error, :unavailable}
  end

  defp existing_reference(state, id, %{"kind" => "item"}) do
    if Map.has_key?(state.items, id), do: :ok, else: {:error, :unavailable}
  end

  defp existing_reference(_state, _id, _attrs), do: {:error, :unavailable}

  defp character(world, id, %{"kind" => "pc", "name" => name}) do
    with {:ok, bundle} <- Systems.Bundle.validate(world.bundle),
         {:ok, sheet} <- Systems.character(bundle),
         do: Systems.actor(bundle, sheet, id, name)
  end

  defp character(_world, _id, _attrs), do: {:ok, nil}

  defp empty_scene(world, id, attrs) when is_map(attrs) do
    with true <- Map.keys(attrs) -- ~w(name description) == [] and Scope.id?(attrs["name"]),
         {:ok, bundle} <- Systems.Bundle.validate(world.bundle),
         {:ok, time} <-
           FictionalTime.new(
             world.id,
             world.calendar_id,
             world.calendar_version,
             world.fictional_time
           ) do
      Systems.scene_rules(bundle)
      |> Map.merge(%{
        scope: struct(Scope, world_id: world.id, generation: world.generation, kind: :published),
        zone_id: id,
        time: time,
        name: attrs["name"],
        description: Map.get(attrs, "description", "")
      })
      |> State.new()
    else
      _ -> {:error, :invalid_record}
    end
  end

  defp empty_scene(_world, _id, _attrs), do: {:error, :invalid_record}

  defp create!(world, user, scene) do
    snapshot = Snapshots.create!(world, scene)
    event = record!(world, user, snapshot, "zone_created", %{})
    Snapshots.checkpoint!(snapshot, event.cursor)
    %{"status" => "published", "entity_id" => scene.zone_id, "zone_id" => scene.zone_id}
  end

  defp draft!(world, user, zone, id, attrs) do
    draft =
      Tx.insert!(Draft, %{
        world_id: world.id,
        zone_id: zone,
        entity_id: id,
        kind: Map.get(attrs, "kind", "zone"),
        attrs: attrs,
        base_revision: world.revision,
        author_id: user
      })

    Tx.event!(world, %{
      scope_key: "authoring",
      kind: "world",
      principal_id: user,
      audience_users: [user],
      event: Codec.dump!(%{type: "draft_saved", result: %{"draft_id" => draft.id}})
    })

    %{"status" => "draft", "entity_id" => id, "zone_id" => zone, "draft_id" => draft.id}
  end

  defp record!(world, user, snapshot, type, transition) do
    world = Tx.update!(world, %{revision: world.revision + 1})

    Tx.event!(world, %{
      snapshot_id: snapshot.id,
      scope_key: snapshot.scope_key,
      kind: "world",
      principal_id: user,
      audience_users: [user],
      transition: transition,
      event: Codec.dump!(%{type: type, result: %{"zone_id" => snapshot.zone_id}})
    })
  end

  @spec window_open?(world_id :: String.t()) :: boolean()
  def window_open?(world),
    do: Repo.exists?(from w in Window, where: w.world_id == ^world and w.status == "open")
end
