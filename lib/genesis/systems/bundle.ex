defmodule Genesis.Systems.Bundle do
  @moduledoc "Closed, versioned JSON bundles. Digests hash canonical sorted-key JSON, not file whitespace."
  alias Genesis.Core.{Check, Formula, Scope}
  alias Genesis.Systems.LocalRules

  @spec validate(data :: term()) :: {:ok, map()} | {:error, :invalid_bundle}
  def validate(data) when is_map(data) do
    with true <- header?(data),
         true <- attributes?(data["attributes"]),
         defaults <- Map.new(data["attributes"], &{&1["id"], &1["default"]}),
         true <- resources?(data["resources"], defaults),
         true <- inventory?(data),
         true <- capabilities?(data["capabilities"]),
         true <- local?(data),
         true <- actions?(data),
         true <- context?(data),
         true <- progression?(data["progression"]),
         true <- milestone_known?(data) do
      digest = :crypto.hash(:sha256, canonical(data)) |> Base.encode16(case: :lower)

      {:ok,
       %{
         data: data,
         ref: %{
           "id" => data["id"],
           "version" => data["version"],
           "format" => 1,
           "digest" => digest
         }
       }}
    else
      _ -> {:error, :invalid_bundle}
    end
  end

  def validate(_data), do: {:error, :invalid_bundle}

  @spec canonical(data :: term()) :: binary()
  def canonical(data) when is_map(data),
    do:
      "{" <>
        (data
         |> Enum.sort()
         |> Enum.map_join(",", fn {k, v} -> Jason.encode!(k) <> ":" <> canonical(v) end)) <> "}"

  def canonical(data) when is_list(data), do: "[" <> Enum.map_join(data, ",", &canonical/1) <> "]"
  def canonical(data), do: Jason.encode!(data)

  defp header?(data),
    do:
      exact?(
        data,
        ~w(format id version attributes resources slots items traits skills actions context_rules capabilities progression) ++
          if(Map.has_key?(data, "local"), do: ["local"], else: [])
      ) and
        data["format"] == 1 and Scope.id?(data["id"]) and integer?(data["version"], 1..100_000)

  defp attributes?(attrs), do: records?(attrs) and Enum.all?(attrs, &attribute?/1)

  defp attribute?(attr),
    do:
      exact?(attr, ~w(id min max default)) and integer?(attr["min"], 0..1000) and
        integer?(attr["max"], attr["min"]..1000) and
        integer?(attr["default"], attr["min"]..attr["max"])

  defp resources?(resources, defaults),
    do: records?(resources) and Enum.all?(resources, &resource?(&1, defaults))

  defp resource?(resource, defaults) do
    with true <- exact?(resource, ~w(id max default)),
         {:ok, maximum} <- Formula.evaluate(resource["max"], defaults) do
      maximum in 1..1_000_000 and integer?(resource["default"], 0..maximum)
    else
      _ -> false
    end
  end

  defp inventory?(data),
    do:
      ids?(data["slots"]) and ids?(data["traits"]) and ids?(data["skills"]) and
        is_map(data["items"]) and map_size(data["items"]) <= 32 and
        Enum.all?(data["items"], fn {id, item} ->
          Scope.id?(id) and exact?(item, ["slot"]) and item["slot"] in data["slots"]
        end)

  defp capabilities?(caps) when is_map(caps) and map_size(caps) <= 32 do
    Enum.all?(caps, fn {name, spec} ->
      capability_shape?(name, spec) and dependencies?(spec, caps)
    end) and Enum.all?(Map.keys(caps), &acyclic?(caps, &1, []))
  end

  defp capabilities?(_caps), do: false

  defp acyclic?(caps, name, path),
    do:
      name not in path and
        Enum.all?(caps[name]["requires"], &acyclic?(caps, &1, [name | path]))

  defp capability_shape?(name, spec),
    do:
      name in ~w(scene checks commerce lore economy production institutions survival) and
        exact?(spec, ~w(status enabled requires)) and
        spec["status"] in ~w(playable record_only deferred) and
        is_boolean(spec["enabled"]) and ids?(spec["requires"]) and
        (not spec["enabled"] or (spec["status"] == "playable" and name != "lore"))

  defp local?(%{"local" => rules} = data) do
    LocalRules.compatible?(rules, data["resources"]) and
      Enum.all?(~w(economy commerce production institutions survival), fn name ->
        match?(%{"status" => "playable", "enabled" => true}, data["capabilities"][name])
      end)
  end

  defp local?(data),
    do:
      Enum.all?(~w(economy commerce production institutions survival), fn name ->
        not match?(%{"enabled" => true}, data["capabilities"][name])
      end)

  defp dependencies?(spec, caps) do
    Enum.all?(spec["requires"], fn name ->
      Map.has_key?(caps, name) and
        (not spec["enabled"] or match?(%{"status" => "playable", "enabled" => true}, caps[name]))
    end)
  end

  defp actions?(data) do
    actions = data["actions"]

    is_map(actions) and map_size(actions) in 1..32 and
      Enum.all?(actions, fn {id, action} ->
        Scope.id?(id) and action?(action, data)
      end)
  end

  defp action?(action, data) do
    with true <- is_map(action),
         true <- action_keys?(action),
         true <- duration?(action["duration"]),
         true <- integer?(action["cost"], 0..1_000_000),
         true <- action["resource"] in Enum.map(data["resources"], & &1["id"]),
         %{"status" => "playable", "enabled" => true} <-
           data["capabilities"][action["capability"]] do
      action_kind?(action, data)
    else
      _ -> false
    end
  end

  defp action_keys?(%{"kind" => kind} = action) do
    extra =
      case kind do
        "take" -> []
        "deed" -> ["fact"]
        "access" -> ["outcome"]
        "check" -> ["attribute", "check"]
        _ -> ["unsupported"]
      end

    exact?(action, ~w(kind duration cost resource capability) ++ extra)
  end

  defp action_keys?(_action), do: false
  defp action_kind?(%{"kind" => "take"}, _data), do: true
  defp action_kind?(%{"kind" => "deed", "fact" => fact}, _data), do: Scope.id?(fact)

  defp action_kind?(%{"kind" => "access", "outcome" => outcome}, _data),
    do: outcome in ~w(admitted confrontation)

  defp action_kind?(%{"kind" => "check", "check" => check, "attribute" => attr}, data),
    do: Check.validate(check) == :ok and attr in Enum.map(data["attributes"], & &1["id"])

  defp action_kind?(_action, _data), do: false

  defp duration?(%{"unit" => "second", "value" => value} = duration),
    do: map_size(duration) == 2 and integer?(value, 0..31_536_000)

  defp duration?(_duration), do: false

  defp context?(data) do
    rules = data["context_rules"]
    records?(rules) and Enum.all?(rules, &context_rule?(&1, data))
  end

  defp context_rule?(rule, data),
    do:
      exact?(rule, ~w(id priority when set)) and
        integer?(rule["priority"], 0..1000) and condition?(rule["when"], data) and
        setters?(rule["set"])

  defp condition?(%{"kind" => "trait", "key" => key} = condition, data),
    do: map_size(condition) == 2 and key in data["traits"]

  defp condition?(%{"kind" => "deed", "key" => key} = condition, data),
    do:
      map_size(condition) == 2 and
        key in Enum.map(data["actions"], fn {_id, action} -> action["fact"] end)

  defp condition?(
         %{"kind" => "companion", "key" => key, "relationship" => relation} = condition,
         data
       ),
       do: map_size(condition) == 3 and key in data["skills"] and relation in ~w(allied hostile)

  defp condition?(_condition, _data), do: false

  defp setters?(set) when is_map(set) and map_size(set) in 1..2 do
    Enum.all?(set, fn
      {"cost", value} -> integer?(value, 0..1_000_000)
      {"outcome", value} -> value in ~w(admitted confrontation)
      _ -> false
    end)
  end

  defp setters?(_set), do: false

  defp progression?(
         %{
           "milestone" => milestone,
           "defeat" => "nonlethal",
           "exceptional_risk" => "permadeath",
           "policy_version" => version,
           "retirement" => "offstage"
         } = progression
       ) do
    map_size(progression) == 5 and exact?(milestone, ~w(id fact award)) and
      Enum.all?(Map.values(milestone), &Scope.id?/1) and integer?(version, 1..100_000)
  end

  defp progression?(_progression), do: false

  defp milestone_known?(data),
    do:
      Enum.any?(data["actions"], fn {_id, action} ->
        action["kind"] == "deed" and action["fact"] == data["progression"]["milestone"]["fact"]
      end)

  defp records?(records) when is_list(records) and length(records) in 1..32,
    do:
      Enum.all?(records, &(is_map(&1) and Scope.id?(&1["id"]))) and
        length(Enum.uniq_by(records, & &1["id"])) == length(records)

  defp records?(_records), do: false

  defp ids?(ids) when is_list(ids) and length(ids) <= 32,
    do: Enum.all?(ids, &Scope.id?/1) and Enum.uniq(ids) == ids

  defp ids?(_ids), do: false
  defp exact?(data, keys) when is_map(data), do: Enum.sort(Map.keys(data)) == Enum.sort(keys)
  defp exact?(_data, _keys), do: false
  defp integer?(value, range), do: is_integer(value) and value in range
end
