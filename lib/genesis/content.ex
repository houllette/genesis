defmodule Genesis.Content do
  @moduledoc "Native workspace read models and the authenticated authoring entry point."
  import Ecto.Query
  alias Genesis.Content.Notes
  alias Genesis.Core.{Scope, State}
  alias Genesis.Engine.Runtime
  alias Genesis.Persistence.{Access, Curation, Draft, Snapshot, Snapshots}
  alias Genesis.{Repo, Worlds}

  @spec create_zone(scope :: term(), world :: String.t(), attrs :: map(), request :: String.t()) ::
          term()
  def create_zone(scope, world, attrs, request),
    do: Runtime.call(scope, world, {:create_zone, attrs, request})

  @spec curate(
          scope :: term(),
          world :: String.t(),
          zone :: String.t(),
          revision :: integer(),
          id :: String.t() | nil,
          attrs :: map(),
          request :: String.t()
        ) :: term()
  def curate(scope, world, zone, revision, id, attrs, request),
    do:
      Runtime.call(
        scope,
        world,
        {:curate, zone, %{revision: revision, id: id, attrs: attrs, request: request}}
      )

  @spec view(scope :: term(), world :: String.t(), zone :: String.t()) ::
          {:ok, map()} | {:error, atom()}
  def view(scope, world, zone) do
    with {:ok, scene} <- scene(scope, world, zone) do
      role =
        if Access.world(scope, world, ["steward", "builder"]) == :ok, do: :gm, else: :spectator

      State.view(scene, %{role: role, actor_id: nil})
    end
  end

  @spec preview(scope :: term(), world :: String.t(), zone :: String.t()) ::
          {:ok, map()} | {:error, atom()}
  def preview(scope, world, zone) do
    with {:ok, scene} <- scene(scope, world, zone),
         do: State.view(scene, %{role: :spectator, actor_id: nil})
  end

  defp scene(scope, world_id, zone) do
    with {:ok, world} <- Worlds.get_world(scope, world_id),
         true <- Scope.id?(zone),
         %Snapshot{} = snapshot <-
           Snapshots.find(
             world_id,
             struct(Scope, world_id: world_id, generation: world.generation, kind: :published),
             zone
           ) do
      Snapshots.load(snapshot)
    else
      {:error, _reason} = error -> error
      _ -> {:error, :unavailable}
    end
  end

  @spec list_zones(scope :: term(), world :: String.t()) :: [map()]
  def list_zones(scope, world_id) do
    case Worlds.get_world(scope, world_id) do
      {:ok, world} -> world |> Snapshots.published() |> Enum.map(&zone_summary/1)
      _ -> []
    end
  end

  defp zone_summary(snapshot) do
    case Snapshots.load(snapshot) do
      {:ok, scene} ->
        %{
          id: scene.zone_id,
          name: scene.name || scene.zone_id,
          description: scene.description,
          revision: scene.revision
        }

      _ ->
        %{
          id: snapshot.zone_id,
          name: "Unavailable record",
          description: "Snapshot validation failed; edits are disabled.",
          revision: nil
        }
    end
  end

  @spec list_drafts(scope :: term(), world :: String.t()) :: [Draft.t()]
  def list_drafts(scope, world) do
    if Access.world(scope, world, ["steward", "builder"]) == :ok,
      do: Repo.all(from d in Draft, where: d.world_id == ^world, order_by: d.inserted_at),
      else: []
  end

  @spec window_open?(scope :: term(), world :: String.t()) :: boolean()
  def window_open?(scope, world),
    do: Access.world(scope, world) == :ok and Curation.window_open?(world)

  @spec save_note(
          scope :: term(),
          world :: String.t(),
          id :: String.t() | nil,
          revision :: integer(),
          attrs :: map(),
          request :: String.t()
        ) :: term()
  defdelegate save_note(scope, world, id, revision, attrs, request), to: Notes, as: :save
  @spec list_notes(scope :: term(), world :: String.t(), opts :: keyword()) :: [map()]
  defdelegate list_notes(scope, world, opts \\ []), to: Notes, as: :list
end
