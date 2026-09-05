defmodule Genesis.Content.NetworkCatalog do
  @moduledoc "Current names and local-site identities read through validated published snapshots. No copied holdings or affiliations."
  import Ecto.Query
  alias Genesis.Core.Settlement
  alias Genesis.Persistence.{Snapshot, Snapshots}
  alias Genesis.{Repo, Worlds}

  @spec load(world :: map(), viewer :: map()) :: {:ok, map()} | {:error, atom()}
  def load(world, viewer) do
    snapshots =
      Repo.all(
        from s in Snapshot,
          where:
            s.world_id == ^world.id and s.generation == ^world.generation and
              s.scope_kind == "published",
          order_by: s.zone_id,
          limit: 81
      )

    if length(snapshots) > 80 do
      {:error, :capacity_limit}
    else
      Enum.reduce_while(
        snapshots,
        {:ok, %{world_id: world.id, generation: world.generation, zones: %{}, institutions: %{}}},
        &load_snapshot(&1, &2, viewer)
      )
    end
  end

  defp load_snapshot(snapshot, {:ok, catalog}, viewer) do
    case Snapshots.load(snapshot) do
      {:ok, state} -> {:cont, {:ok, add(catalog, state, viewer)}}
      _ -> {:halt, {:error, :unavailable}}
    end
  end

  defp add(catalog, state, viewer) do
    catalog = put_in(catalog.zones[state.zone_id], %{id: state.zone_id, name: state.name})

    case state.settlement do
      nil ->
        catalog

      local ->
        id = institution_id(catalog.world_id, state.zone_id, local["id"])

        record = %{
          id: id,
          home_zone: state.zone_id,
          local_id: local["id"],
          name: local["name"],
          visible: not is_nil(Settlement.view(state, viewer))
        }

        put_in(catalog.institutions[id], record)
    end
  end

  @doc "Preserves the reference introduced by atlas 07A; registration does not rename the institution."
  @spec institution_id(world :: String.t(), zone :: String.t(), local :: String.t()) :: String.t()
  def institution_id(world, zone, local), do: Worlds.named_id([world, "institution", zone, local])
end
