defmodule Genesis.Core.AtlasRecordTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.AtlasRecord

  test "nested places reject cycles and references cannot cross type or invent runtime state" do
    catalog = %{
      "record:region" => %{kind: "region", parent: nil, archived: false},
      "record:town" => %{kind: "location", parent: "record:region", archived: false},
      "actor:moll" => %{kind: "actor", parent: nil, archived: false}
    }

    attrs = %{"kind" => "region", "name" => "Reach", "parent" => "record:town"}
    assert {:error, :location_cycle} = AtlasRecord.validate("record:region", attrs, catalog)

    assert {:error, :invalid_reference} =
             AtlasRecord.validate("record:new", %{attrs | "parent" => "actor:moll"}, catalog)

    assert {:error, :invalid_reference} =
             AtlasRecord.validate("record:new", %{attrs | "parent" => "absent"}, catalog)

    assert {:ok, result} =
             AtlasRecord.validate("record:new", %{attrs | "parent" => "record:region"}, catalog)

    assert result["visibility"] == "gm"
    assert result["archived"] == false
    assert {:ok, ^result} = AtlasRecord.restore(Map.put(result, "version", 1))

    assert {:error, :unsupported_atlas_format} =
             AtlasRecord.restore(Map.put(result, "version", 2))

    for fields <- [%{"stock" => 12}, %{"note:units" => 1.1}, %{"note:code" => fn -> :unsafe end}] do
      assert {:error, :invalid_record} =
               AtlasRecord.validate("record:new", Map.put(attrs, "fields", fields), catalog)
    end

    assert {:ok, _} =
             AtlasRecord.validate(
               "record:new",
               %{
                 "kind" => "article",
                 "name" => "Lore",
                 "fields" => %{"note:era" => "Before the flood"}
               },
               catalog
             )
  end

  test "routes validate concrete endpoints and bounded record-only condition/capacity" do
    catalog = Map.new(~w(a b), &{"zone:" <> &1, %{kind: "zone", archived: false}})

    attrs = %{
      "kind" => "route",
      "name" => "Bridge",
      "source" => "zone:a",
      "target" => "zone:b",
      "fields" => %{"condition" => "damaged", "capacity" => 3}
    }

    assert {:ok, checked} = AtlasRecord.validate("route", attrs, catalog)
    assert checked["fields"]["capacity"] == 3

    assert {:error, :invalid_record} =
             AtlasRecord.validate("route", put_in(attrs["fields"]["capacity"], 0), catalog)

    assert {:error, :invalid_reference} =
             AtlasRecord.validate("route", %{attrs | "target" => "zone:missing"}, catalog)

    archived = put_in(catalog["zone:b"].archived, true)
    assert {:error, :invalid_reference} = AtlasRecord.validate("route", attrs, archived)
  end
end
