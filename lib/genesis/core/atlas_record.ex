defmodule Genesis.Core.AtlasRecord do
  @moduledoc "Closed, bounded descriptive records and directed links. No field grants inventory, affiliation, knowledge or travel."
  alias Genesis.Core.Scope

  @kinds ~w(region location organisation family article culture language route resource_site relationship)
  @relations ~w(located_in affiliated_with kin_of speaks documents connected_to)
  @defaults %{
    "body" => "",
    "tags" => [],
    "parent" => nil,
    "source" => nil,
    "target" => nil,
    "relation" => nil,
    "fields" => %{},
    "archived" => false,
    "visibility" => "gm",
    "campaign_id" => nil
  }

  @spec kinds() :: [String.t()]
  def kinds, do: @kinds
  @spec relations() :: [String.t()]
  def relations, do: @relations

  @spec validate(id :: String.t(), attrs :: term(), catalog :: map()) ::
          {:ok, map()} | {:error, atom()}
  def validate(id, attrs, catalog) when is_map(attrs) do
    record = Map.merge(@defaults, attrs)

    cond do
      Map.keys(attrs) -- (Map.keys(@defaults) ++ ~w(kind name)) != [] -> {:error, :invalid_record}
      not valid_fields?(record) -> {:error, :invalid_record}
      not references?(record, catalog) -> {:error, :invalid_reference}
      cycle?(id, record["parent"], catalog, %{}) -> {:error, :location_cycle}
      true -> {:ok, record}
    end
  end

  def validate(_id, _attrs, _catalog), do: {:error, :invalid_record}

  @doc "Validates stored version/shape without invalidating retained links to later-archived targets."
  @spec restore(data :: term()) :: {:ok, map()} | {:error, :unsupported_atlas_format}
  def restore(%{"version" => 1} = data) do
    attrs = Map.delete(data, "version")
    keys = Map.keys(@defaults) ++ ~w(kind name)

    if Enum.sort(Map.keys(attrs)) == Enum.sort(keys) and valid_fields?(attrs),
      do: {:ok, attrs},
      else: {:error, :unsupported_atlas_format}
  end

  def restore(_data), do: {:error, :unsupported_atlas_format}

  defp valid_fields?(r),
    do:
      r["kind"] in @kinds and Scope.id?(r["name"]) and text?(r["body"], 10_000) and
        tags?(r["tags"]) and is_boolean(r["archived"]) and audience?(r) and
        fields?(r["kind"], r["fields"]) and endpoints?(r)

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) <= max and String.valid?(value)

  defp tags?(tags) when is_list(tags) and length(tags) <= 16,
    do: Enum.all?(tags, &Scope.id?/1) and Enum.uniq(tags) == tags

  defp tags?(_tags), do: false
  defp audience?(%{"visibility" => "party", "campaign_id" => id}), do: Scope.id?(id)

  defp audience?(%{"visibility" => visibility, "campaign_id" => nil}),
    do: visibility in ~w(public gm)

  defp audience?(_record), do: false

  # These fields are record-only descriptions, not runtime policies or stock.
  defp fields?("route", %{"condition" => condition, "capacity" => capacity} = fields),
    do:
      map_size(fields) == 2 and condition in ~w(open damaged closed) and is_integer(capacity) and
        capacity in 1..1000

  defp fields?("resource_site", %{"resource" => resource} = fields),
    do: map_size(fields) == 1 and Scope.id?(resource)

  defp fields?(kind, fields)
       when kind not in ["route", "resource_site"] and is_map(fields) and map_size(fields) <= 8,
       do:
         Enum.all?(fields, fn {key, value} ->
           # Namespaced annotations cannot masquerade as canonical mechanics.
           is_binary(key) and String.starts_with?(key, "note:") and Scope.id?(key) and
             scalar?(value)
         end)

  defp fields?(_kind, _fields), do: false
  defp scalar?(value) when is_boolean(value), do: true
  defp scalar?(value) when is_integer(value), do: abs(value) <= 1_000_000
  defp scalar?(value), do: text?(value, 512)

  defp endpoints?(%{"kind" => "relationship"} = r),
    do:
      r["relation"] in @relations and reference?(r["source"]) and reference?(r["target"]) and
        r["source"] != r["target"] and is_nil(r["parent"])

  defp endpoints?(%{"kind" => "route"} = r),
    do:
      reference?(r["source"]) and reference?(r["target"]) and r["source"] != r["target"] and
        is_nil(r["relation"]) and is_nil(r["parent"])

  defp endpoints?(r),
    do:
      is_nil(r["source"]) and is_nil(r["target"]) and is_nil(r["relation"]) and
        (is_nil(r["parent"]) or (r["kind"] in ~w(region location) and reference?(r["parent"])))

  defp reference?(ref), do: is_binary(ref) and byte_size(ref) in 1..300 and String.valid?(ref)

  defp references?(r, catalog) do
    parent = r["parent"]
    refs = Enum.reject([parent, r["source"], r["target"]], &is_nil/1)

    Enum.all?(refs, &active_target?(catalog[&1])) and
      (is_nil(parent) or place?(catalog[parent])) and
      (r["kind"] != "route" or (place?(catalog[r["source"]]) and place?(catalog[r["target"]])))
  end

  defp active_target?(%{archived: false, kind: kind}), do: kind not in ~w(relationship route)
  defp active_target?(_target), do: false
  defp place?(%{kind: kind}), do: kind in ~w(region location zone)
  defp place?(_target), do: false

  defp cycle?(_id, nil, _catalog, _seen), do: false
  defp cycle?(id, id, _catalog, _seen), do: true

  defp cycle?(id, parent, catalog, seen) do
    Map.has_key?(seen, parent) or
      cycle?(id, Map.get(catalog[parent] || %{}, :parent), catalog, Map.put(seen, parent, true))
  end
end
