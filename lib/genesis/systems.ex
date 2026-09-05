defmodule Genesis.Systems do
  @moduledoc "Loads original bounded rulesets. Validation and resolution remain transport independent."
  alias Genesis.Core.Actor
  alias Genesis.Systems.{Bundle, Declarative}

  # Ship only these reviewed demo assets; there is no caller-controlled runtime
  # filesystem loader. Resource tracking recompiles this module after JSON edits.
  @fantasy_path Path.expand("../../priv/systems/fantasy_demo.json", __DIR__)
  @cyberpunk_path Path.expand("../../priv/systems/cyberpunk_demo.json", __DIR__)
  @external_resource @fantasy_path
  @external_resource @cyberpunk_path
  @fantasy File.read!(@fantasy_path)
  @cyberpunk File.read!(@cyberpunk_path)

  @spec load(id :: String.t()) :: {:ok, map()} | {:error, term()}
  def load("fantasy_demo"), do: decode(@fantasy)
  def load("cyberpunk_demo"), do: decode(@cyberpunk)
  def load(_id), do: {:error, :unknown_bundle}

  defp decode(bytes) do
    with {:ok, data} <- Jason.decode(bytes), do: Bundle.validate(data)
  end

  @spec character(bundle :: map(), attrs :: map()) :: {:ok, map()} | {:error, atom()}
  def character(bundle, attrs \\ %{}), do: Declarative.character(bundle, attrs)

  @spec actor(bundle :: map(), sheet :: map(), id :: String.t(), name :: String.t()) ::
          {:ok, Actor.t()} | {:error, atom()}
  def actor(bundle, sheet, id, name) do
    with :ok <- Declarative.validate_character(bundle, sheet) do
      {:ok,
       struct(Actor,
         id: id,
         name: name,
         kind: :pc,
         skills: sheet["attributes"],
         resources: sheet["resources"],
         traits: sheet["traits"]
       )}
    end
  end

  @spec scene_rules(bundle :: map()) :: map()
  def scene_rules(bundle) do
    actions =
      Map.new(bundle.data["actions"], fn {id, action} ->
        {id, Map.put(action, "duration", action["duration"]["value"])}
      end)

    %{rules_ref: bundle.ref, actions: actions, context_rules: bundle.data["context_rules"]}
  end

  @spec capability(bundle :: map(), name :: String.t()) :: :ok | {:error, :unsupported_capability}
  def capability(bundle, name) do
    case bundle.data["capabilities"][name] do
      %{"status" => "playable", "enabled" => true} -> :ok
      _ -> {:error, :unsupported_capability}
    end
  end
end
