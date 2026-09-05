defmodule Genesis.Persistence.Codec do
  @moduledoc "Versioned, closed data encoding for durable engine values."
  alias Genesis.Core.{Actor, FictionalTime, Item, Knowledge, Proposal, Scope, State}

  @structs %{
    "actor" => Actor,
    "time" => FictionalTime,
    "item" => Item,
    "knowledge" => Knowledge,
    "proposal" => Proposal,
    "scope" => Scope,
    "state" => State
  }
  @atoms ~w(id name kind companion_of traits skills resources revision alive retired audience
    scope zone_id time rules_ref actors items knowledge actions context_rules elapsed status events
    world_id generation window_id calendar_id calendar_version value unit subject_id object_id
    predicate occurred_at learned_at recorded_at source_ids version owner quantity actor_id
    intent terms type target_id result variants draws resolution read_set total outcome capped
    expected_revision event_id sources check_result public gm player spectator pc npc zone actor
    event fact observation belief relationship obligation memory published experience candidate rehearsal
    second active paused success partial failure request_id campaign_id principal_id payload effects
    durability durable ephemeral deadline remaining_ms policy_version risk accepted format after before
    participants causal_parent_ids causal_root_id affected_ids operator_id gathering_id plan_id step_index
    direct confirm event_ids user_id snapshot_id pause resume ready step persona description)a
  @atom_lookup Map.new(@atoms, &{Atom.to_string(&1), &1})

  @spec dump(value :: term()) :: {:ok, map()} | {:error, atom()}
  def dump(value) do
    guard_format(fn ->
      stored = %{"format" => 1, "value" => pack(value, 0)}
      bounded!(stored)
      stored
    end)
  end

  @spec load(value :: term()) :: {:ok, term()} | {:error, atom()}
  def load(%{"format" => 1, "value" => value} = stored) when map_size(stored) == 2,
    do:
      guard_format(fn ->
        bounded!(stored)
        unpack(value, 0)
      end)

  def load(_value), do: {:error, :unsupported_format}

  @spec load_state(value :: term()) :: {:ok, Genesis.Core.State.t()} | {:error, atom()}
  def load_state(value) do
    with {:ok, state} <- load(value), do: State.restore(state)
  end

  @spec dump!(value :: term()) :: map()
  def dump!(value) do
    case dump(value) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise ArgumentError, "unsupported durable value: #{reason}"
    end
  end

  @spec digest(value :: term()) :: String.t()
  def digest(value),
    do: :crypto.hash(:sha256, Jason.encode!(dump!(value))) |> Base.encode16(case: :lower)

  defp guard_format(fun) do
    {:ok, fun.()}
  catch
    :invalid_format -> {:error, :invalid_format}
  end

  defp bounded!(value) do
    case Jason.encode(value) do
      {:ok, bytes} when byte_size(bytes) <= 2_000_000 -> :ok
      _ -> throw(:invalid_format)
    end
  end

  defp pack(_value, depth) when depth > 32, do: throw(:invalid_format)

  defp pack(value, _depth) when is_nil(value) or is_boolean(value) or is_integer(value),
    do: ["v", value]

  defp pack(value, _depth) when is_binary(value) and byte_size(value) <= 65_536 do
    if String.valid?(value), do: ["s", value], else: throw(:invalid_format)
  end

  defp pack(value, _depth) when value in @atoms, do: ["a", Atom.to_string(value)]

  defp pack(%DateTime{time_zone: "Etc/UTC", utc_offset: 0, std_offset: 0} = value, _depth),
    do: ["utc", DateTime.to_iso8601(value)]

  defp pack(%{__struct__: module} = value, depth) do
    case Enum.find(@structs, fn {_tag, known} -> known == module end) do
      {tag, _module} -> ["struct", tag, pack(Map.from_struct(value), depth + 1)]
      _ -> throw(:invalid_format)
    end
  end

  defp pack(value, depth) when is_map(value) and map_size(value) <= 5000,
    do: [
      "map",
      value |> Enum.map(fn {k, v} -> [pack(k, depth + 1), pack(v, depth + 1)] end) |> Enum.sort()
    ]

  defp pack(value, depth) when is_list(value) and length(value) <= 5000,
    do: ["list", Enum.map(value, &pack(&1, depth + 1))]

  defp pack(value, depth) when is_tuple(value) and tuple_size(value) <= 16,
    do: ["tuple", value |> Tuple.to_list() |> Enum.map(&pack(&1, depth + 1))]

  defp pack(_value, _depth), do: throw(:invalid_format)

  defp unpack(_value, depth) when depth > 32, do: throw(:invalid_format)

  defp unpack(["v", value], _depth) when is_nil(value) or is_boolean(value) or is_integer(value),
    do: value

  defp unpack(["s", value], _depth) when is_binary(value) and byte_size(value) <= 65_536,
    do: value

  defp unpack(["a", value], _depth), do: Map.get(@atom_lookup, value) || throw(:invalid_format)

  defp unpack(["utc", value], _depth) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, 0} -> time
      _ -> throw(:invalid_format)
    end
  end

  defp unpack(["struct", tag, value], depth) do
    module = Map.get(@structs, tag) || throw(:invalid_format)
    fields = unpack(value, depth + 1)
    defaults = Map.from_struct(struct(module))

    if is_map(fields) and Enum.sort(Map.keys(fields)) == Enum.sort(Map.keys(defaults)),
      do: struct(module, fields),
      else: throw(:invalid_format)
  end

  defp unpack(["map", entries], depth) when is_list(entries) and length(entries) <= 5000 do
    pairs =
      Enum.map(entries, fn
        [key, value] -> {unpack(key, depth + 1), unpack(value, depth + 1)}
        _ -> throw(:invalid_format)
      end)

    result = Map.new(pairs)
    if map_size(result) == length(entries), do: result, else: throw(:invalid_format)
  end

  defp unpack(["list", values], depth) when is_list(values) and length(values) <= 5000,
    do: Enum.map(values, &unpack(&1, depth + 1))

  defp unpack(["tuple", values], depth) when is_list(values) and length(values) <= 16,
    do: values |> Enum.map(&unpack(&1, depth + 1)) |> List.to_tuple()

  defp unpack(_value, _depth), do: throw(:invalid_format)
end
