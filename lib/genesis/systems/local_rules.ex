defmodule Genesis.Systems.LocalRules do
  @moduledoc "Reviewed local mechanic definitions, separate from live holdings and WorldProfile choices."
  alias Genesis.Core.Scope

  @spec defaults() :: map()
  def defaults do
    %{
      "version" => 1,
      "commodities" => %{
        "grain" => "Grain",
        "ration" => "Rations",
        "chaff" => "Chaff",
        "coin" => "Copper minor units"
      },
      "currency" => "coin",
      "recipe" => %{
        "id" => "mill",
        "input" => "grain",
        "input_units" => 2,
        "output" => "ration",
        "output_units" => 1,
        "waste" => "chaff",
        "waste_units" => 1,
        "delay" => 0
      },
      "rest" => %{
        "supply" => "ration",
        "quantity" => 1,
        "resource" => "effort",
        "gain" => 2,
        "maximum" => 10,
        "duration" => 3600
      },
      "barter" => %{
        "give" => "ration",
        "give_units" => 1,
        "receive" => "grain",
        "receive_units" => 2
      },
      "offering" => %{"commodity" => "ration", "quantity" => 1},
      "aid" => %{"commodity" => "grain", "quantity" => 1}
    }
  end

  @spec valid?(rules :: term()) :: boolean()
  def valid?(rules) when is_map(rules) do
    exact?(rules, ~w(version commodities currency recipe rest barter offering aid)) and
      rules["version"] == 1 and commodities?(rules["commodities"]) and
      Map.has_key?(rules["commodities"], rules["currency"]) and
      recipe?(rules["recipe"], rules["commodities"]) and
      rules["currency"] not in Enum.map(~w(input output waste), &rules["recipe"][&1]) and
      supporting_rules?(rules)
  end

  def valid?(_rules), do: false

  defp supporting_rules?(rules) do
    rest?(rules["rest"], rules["commodities"]) and
      barter?(rules["barter"], rules["commodities"]) and
      amount?(rules["offering"], rules["commodities"]) and
      amount?(rules["aid"], rules["commodities"])
  end

  @spec compatible?(rules :: map(), resources :: list()) :: boolean()
  def compatible?(rules, resources) do
    valid?(rules) and
      Enum.any?(resources, fn resource ->
        resource["id"] == rules["rest"]["resource"] and
          resource["max"] == rules["rest"]["maximum"]
      end)
  end

  defp commodities?(values) when is_map(values) and map_size(values) in 4..16,
    do: Enum.all?(values, fn {id, label} -> Scope.id?(id) and Scope.id?(label) end)

  defp commodities?(_values), do: false

  defp recipe?(r, commodities) do
    exact?(r, ~w(id input input_units output output_units waste waste_units delay)) and
      Scope.id?(r["id"]) and r["delay"] == 0 and
      Enum.all?(~w(input output waste), &Map.has_key?(commodities, r[&1])) and
      length(Enum.uniq(Enum.map(~w(input output waste), &r[&1]))) == 3 and
      Enum.all?(~w(input_units output_units waste_units), &positive?(r[&1])) and
      r["input_units"] == r["output_units"] + r["waste_units"]
  end

  defp rest?(r, commodities),
    do:
      exact?(r, ~w(supply quantity resource gain maximum duration)) and
        Map.has_key?(commodities, r["supply"]) and Scope.id?(r["resource"]) and
        Enum.all?(~w(quantity gain maximum), &positive?(r[&1])) and r["gain"] <= r["maximum"] and
        is_integer(r["duration"]) and r["duration"] in 0..86_400

  defp barter?(b, commodities),
    do:
      exact?(b, ~w(give give_units receive receive_units)) and
        Map.has_key?(commodities, b["give"]) and Map.has_key?(commodities, b["receive"]) and
        b["give"] != b["receive"] and positive?(b["give_units"]) and positive?(b["receive_units"])

  defp amount?(a, commodities),
    do:
      exact?(a, ~w(commodity quantity)) and Map.has_key?(commodities, a["commodity"]) and
        positive?(a["quantity"])

  defp positive?(n), do: is_integer(n) and n in 1..1000
  defp exact?(m, keys) when is_map(m), do: Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp exact?(_m, _keys), do: false
end
