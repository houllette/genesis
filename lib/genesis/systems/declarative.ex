defmodule Genesis.Systems.Declarative do
  @moduledoc "One implementation interprets both demo bundles, including all character validation."
  @behaviour Genesis.Systems.GameSystem
  alias Genesis.Core.{Check, Formula}

  @impl true
  @spec metadata(bundle :: map()) :: map()
  def metadata(bundle), do: Map.take(bundle.data, ~w(attributes resources slots items traits))

  @spec character(bundle :: map(), attrs :: map()) :: {:ok, map()} | {:error, atom()}
  def character(bundle, attrs) when is_map(attrs) do
    defaults = %{
      "attributes" => Map.new(bundle.data["attributes"], &{&1["id"], &1["default"]}),
      "resources" => Map.new(bundle.data["resources"], &{&1["id"], &1["default"]}),
      "equipment" => %{},
      "traits" => [],
      "bundle" => bundle.ref
    }

    character = Map.merge(defaults, attrs)
    with :ok <- validate_character(bundle, character), do: {:ok, character}
  end

  def character(_bundle, _attrs), do: {:error, :invalid_character}

  @impl true
  @spec validate_character(bundle :: map(), character :: map()) :: :ok | {:error, atom()}
  def validate_character(bundle, character) when is_map(character) do
    valid =
      Enum.sort(Map.keys(character)) == ~w(attributes bundle equipment resources traits) and
        character["bundle"] == bundle.ref and
        attributes?(character["attributes"], bundle.data["attributes"]) and
        resources?(character["resources"], character["attributes"], bundle.data["resources"]) and
        equipment?(character["equipment"], bundle.data) and
        traits?(character["traits"], bundle.data["traits"])

    if valid, do: :ok, else: {:error, :invalid_character}
  end

  def validate_character(_bundle, _character), do: {:error, :invalid_character}

  @impl true
  @spec resolve(
          bundle :: map(),
          character :: map(),
          action_id :: String.t(),
          draws :: [integer()]
        ) ::
          {:ok, map(), map()} | {:error, atom()}
  def resolve(bundle, character, action_id, draws) do
    with :ok <- validate_character(bundle, character),
         %{"kind" => "check"} = action <- bundle.data["actions"][action_id],
         true <- character["resources"][action["resource"]] >= action["cost"],
         {:ok, check} <-
           Check.prepare(action["check"], character["attributes"][action["attribute"]]),
         {:ok, result} <- Check.resolve(check, draws) do
      next = update_in(character["resources"][action["resource"]], &(&1 - action["cost"]))
      {:ok, next, Map.put(result, :duration, action["duration"])}
    else
      {:error, _reason} = error -> error
      false -> {:error, :insufficient_resources}
      _ -> {:error, :unsupported_action}
    end
  end

  defp attributes?(values, specs) when is_map(values) do
    Enum.sort(Map.keys(values)) == Enum.sort(Enum.map(specs, & &1["id"])) and
      Enum.all?(specs, fn spec -> bounded?(values[spec["id"]], spec["min"], spec["max"]) end)
  end

  defp attributes?(_values, _specs), do: false

  defp resources?(values, attrs, specs) when is_map(values) do
    Enum.sort(Map.keys(values)) == Enum.sort(Enum.map(specs, & &1["id"])) and
      Enum.all?(specs, fn spec ->
        case Formula.evaluate(spec["max"], attrs) do
          {:ok, max} -> max in 1..1_000_000 and bounded?(values[spec["id"]], 0, max)
          _ -> false
        end
      end)
  end

  defp resources?(_values, _attrs, _specs), do: false

  defp equipment?(equipment, data) when is_map(equipment) do
    values = Map.values(equipment)

    Enum.uniq(values) == values and
      Enum.all?(equipment, fn {slot, item} ->
        slot in data["slots"] and match?(%{"slot" => ^slot}, data["items"][item])
      end)
  end

  defp equipment?(_equipment, _data), do: false

  defp traits?(traits, allowed) when is_list(traits),
    do: Enum.uniq(traits) == traits and Enum.all?(traits, &(&1 in allowed))

  defp traits?(_traits, _allowed), do: false
  defp bounded?(value, min, max), do: is_integer(value) and value >= min and value <= max
end
