defmodule Genesis.Core.Network do
  @moduledoc "Bounded World-owned connectivity and institution jurisdictions. No movement, stock, or local standing writer."
  alias Genesis.Core.Scope

  @spec new(world :: String.t(), generation :: non_neg_integer()) :: map()
  def new(world, generation),
    do: %{
      "version" => 1,
      "world_id" => world,
      "generation" => generation,
      "connections" => [],
      "institutions" => %{}
    }

  @doc "The catalog contains trusted current published zone IDs and local institution identities."
  @spec restore(data :: term(), catalog :: map()) :: {:ok, map()} | {:error, atom()}
  def restore(data, catalog) when is_map(data) do
    if Enum.sort(Map.keys(data)) == ~w(connections generation institutions version world_id) and
         data["version"] == 1 and data["world_id"] == catalog.world_id and
         data["generation"] == catalog.generation and
         connections?(data["connections"], catalog) and
         institutions?(data["institutions"], catalog),
       do: {:ok, data},
       else: {:error, :invalid_network}
  end

  def restore(_data, _catalog), do: {:error, :invalid_network}

  @spec apply(data :: map(), command :: term(), catalog :: map()) ::
          {:ok, map()} | {:error, atom()}
  def apply(data, %{"type" => "connection"} = command, catalog) do
    edge = Map.delete(command, "type")

    with {:ok, _} <- restore(data, catalog), true <- connection?(edge, catalog) do
      edges = Enum.reject(data["connections"], &(pair(&1) == pair(edge)))
      restore(%{data | "connections" => Enum.sort_by([edge | edges], &pair/1)}, catalog)
    else
      _ -> {:error, :invalid_connection}
    end
  end

  def apply(data, %{"type" => "jurisdiction", "institution_id" => id} = command, catalog) do
    with {:ok, _} <- restore(data, catalog),
         true <- Enum.sort(Map.keys(command)) == ~w(institution_id type visibility zones),
         %{} = local <- catalog.institutions[id] do
      institution = %{
        "home_zone" => local.home_zone,
        "local_id" => local.local_id,
        "zones" => command["zones"],
        "visibility" => command["visibility"]
      }

      restore(put_in(data["institutions"][id], institution), catalog)
    else
      _ -> {:error, :invalid_jurisdiction}
    end
  end

  def apply(_data, _command, _catalog), do: {:error, :unsupported_operation}

  @doc "A geography-only assessment, not admission, a reservation, or permission to move an actor. Damaged links block passage."
  @spec assess(data :: map(), from :: String.t(), to :: String.t(), size :: pos_integer()) ::
          :ok | {:error, atom()}
  def assess(data, from, to, size) when is_integer(size) and size in 1..1000 do
    case Enum.find(data["connections"], &(pair(&1) == {from, to})) do
      %{"condition" => "open", "capacity" => capacity} when size <= capacity -> :ok
      %{"condition" => "open"} -> {:error, :capacity_exceeded}
      _ -> {:error, :route_unavailable}
    end
  end

  def assess(_data, _from, _to, _size), do: {:error, :invalid_party_size}

  defp connections?(edges, catalog) when is_list(edges) and length(edges) <= 160,
    do:
      Enum.all?(edges, &connection?(&1, catalog)) and
        length(Enum.uniq_by(edges, &pair/1)) == length(edges)

  defp connections?(_edges, _catalog), do: false

  defp connection?(edge, catalog) when is_map(edge),
    do:
      Enum.sort(Map.keys(edge)) == ~w(capacity condition from to visibility) and
        edge["from"] != edge["to"] and
        Enum.all?([edge["from"], edge["to"]], &Map.has_key?(catalog.zones, &1)) and
        edge["condition"] in ~w(open damaged closed) and
        is_integer(edge["capacity"]) and edge["capacity"] in 1..1000 and
        edge["visibility"] in ~w(public gm)

  defp connection?(_edge, _catalog), do: false
  defp pair(edge), do: {edge["from"], edge["to"]}

  defp institutions?(rows, catalog) when is_map(rows) and map_size(rows) <= 80,
    do: Enum.all?(rows, fn {id, row} -> institution?(id, row, catalog) end)

  defp institutions?(_rows, _catalog), do: false

  defp institution?(id, row, catalog) when is_map(row) do
    local = catalog.institutions[id]

    Scope.id?(id) and not is_nil(local) and
      Enum.sort(Map.keys(row)) == ~w(home_zone local_id visibility zones) and
      row["home_zone"] == local.home_zone and row["local_id"] == local.local_id and
      row["visibility"] in ~w(public gm) and zones?(row["zones"], row["home_zone"], catalog)
  end

  defp institution?(_id, _row, _catalog), do: false

  defp zones?(zones, home, catalog) when is_list(zones) and length(zones) in 1..80,
    do:
      home in zones and Enum.uniq(zones) == zones and
        Enum.all?(zones, &Map.has_key?(catalog.zones, &1))

  defp zones?(_zones, _home, _catalog), do: false
end
