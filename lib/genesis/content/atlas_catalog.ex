defmodule Genesis.Content.AtlasCatalog do
  @moduledoc "Read-through atlas identity: names and owning locations come from validated scoped snapshots."
  import Ecto.Query
  alias Genesis.Content.NetworkCatalog
  alias Genesis.Core.State
  alias Genesis.Persistence.{Snapshot, Snapshots}
  alias Genesis.Repo

  @spec published(world :: map(), viewer :: map()) :: {:ok, [map()]} | {:error, atom()}
  def published(world, viewer) do
    snapshots =
      Repo.all(
        from s in Snapshot,
          where:
            s.world_id == ^world.id and s.generation == ^world.generation and
              s.scope_kind == "published",
          order_by: s.zone_id,
          limit: 81
      )

    if length(snapshots) <= 80, do: runtime(snapshots, viewer), else: {:error, :capacity_limit}
  end

  @spec entry(row :: map()) :: map()
  def entry(row) do
    data = row.data

    %{
      id: "record:" <> row.id,
      record_id: row.id,
      kind: row.kind,
      name: data["name"],
      body: data["body"],
      tags: data["tags"],
      parent: data["parent"],
      source: data["source"],
      target: data["target"],
      relation: data["relation"],
      fields: data["fields"],
      archived: row.archived,
      revision: row.revision,
      visibility: row.visibility,
      campaign_id: row.campaign_id,
      editable: true,
      source_ids: [],
      zone_id: nil
    }
  end

  @spec runtime(snapshots :: list(), viewer :: map()) :: {:ok, [map()]} | {:error, atom()}
  def runtime(snapshots, viewer) do
    Enum.reduce_while(snapshots, {:ok, []}, fn snapshot, {:ok, acc} ->
      with {:ok, state} <- Snapshots.load(snapshot), {:ok, view} <- State.view(state, viewer) do
        {:cont, {:ok, acc ++ records(view)}}
      else
        _ -> {:halt, {:error, :unavailable}}
      end
    end)
  end

  defp records(view) do
    [runtime_record("zone", view.zone_id, view.name, view.description, view.zone_id)] ++
      Enum.map(view.actors, &runtime_record("actor", &1.id, &1.name, "", view.zone_id)) ++
      Enum.map(view.items, &runtime_record("item", &1.id, &1.name, "", view.zone_id)) ++
      institution(view) ++
      Enum.map(view.knowledge, fn record ->
        runtime_record(
          "knowledge",
          record.id,
          "#{record.kind}: #{record.predicate}",
          to_string(record.value),
          view.zone_id
        )
        |> Map.put(:source_ids, Map.get(record, :source_ids, []))
      end)
  end

  defp institution(%{settlement: nil}), do: []

  defp institution(view) do
    settlement = view.settlement

    [
      runtime_record(
        "institution",
        NetworkCatalog.institution_id(view.scope.world_id, view.zone_id, settlement["id"]),
        settlement["name"],
        "Local institution; stock, affiliations and policy remain with its place.",
        view.zone_id
      )
    ]
  end

  defp runtime_record(kind, id, name, body, zone),
    do: %{
      id: kind <> ":" <> id,
      record_id: nil,
      kind: kind,
      name: name,
      body: body,
      tags: [],
      parent: nil,
      source: nil,
      target: nil,
      relation: nil,
      fields: %{},
      archived: false,
      revision: nil,
      visibility: nil,
      campaign_id: nil,
      editable: false,
      source_ids: [],
      zone_id: zone
    }

  @doc "Filter endpoints before search, ranking, counts, snippets and backlinks. Hidden ancestors are omitted."
  @spec linked(records :: [map()]) :: [map()]
  def linked(records) do
    targets =
      records
      |> Enum.reject(&(&1.archived or &1.kind in ~w(relationship route)))
      |> Map.new(&{&1.id, &1})

    records
    |> Enum.filter(fn r ->
      Enum.all?(Enum.reject([r.source, r.target], &is_nil/1), &Map.has_key?(targets, &1))
    end)
    |> Enum.map(fn r -> if Map.has_key?(targets, r.parent), do: r, else: %{r | parent: nil} end)
  end

  @spec page(records :: [map()], query :: String.t()) :: map()
  def page(records, query) do
    needle = String.downcase(query)

    matches =
      records
      |> Enum.filter(&matches?(&1, needle))
      |> Enum.sort_by(&{String.downcase(&1.name), &1.id})

    %{records: Enum.take(matches, 50), count: length(matches), more: length(matches) > 50}
  end

  defp matches?(record, needle),
    do:
      Enum.any?(
        [record.name, record.body | record.tags],
        &String.contains?(String.downcase(&1), needle)
      )
end
