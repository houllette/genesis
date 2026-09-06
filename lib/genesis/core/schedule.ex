defmodule Genesis.Core.Schedule do
  @moduledoc "Versioned, bounded deterministic schedules owned by the containing Zone."
  alias Genesis.Core.{LocalAction, Scope}

  @spec fields() :: [String.t()]
  def fields,
    do:
      ~w(kind name version first_at every until actor_id action target_id quantity availability condition dependency)

  @spec configure(state :: map(), id :: String.t(), attrs :: map()) :: term()
  def configure(state, id, attrs) do
    schedule = Map.drop(attrs, ["kind"])

    timeline =
      state.timeline ||
        %{"format" => 1, "schedules" => %{}, "next" => %{}, "condition" => "normal"}

    previous = timeline["schedules"][id]

    if valid?(schedule) and schedule["first_at"] > state.time.value and
         (is_nil(previous) or schedule["version"] > previous["version"]) and
         (not is_nil(previous) or map_size(timeline["schedules"]) < 16) and
         actor?(state, schedule) do
      timeline =
        timeline
        |> put_in(["schedules", id], schedule)
        |> put_in(["next", id], schedule["first_at"])

      {:ok, %{state | timeline: timeline}}
    else
      {:error, :invalid_schedule}
    end
  end

  @spec valid?(value :: term()) :: boolean()
  def valid?(value) when is_map(value) do
    Map.keys(value) -- (fields() -- ["kind"]) == [] and
      Scope.id?(value["name"]) and is_integer(value["version"]) and value["version"] in 1..1000 and
      timing?(value) and
      availability?(value["availability"]) and dependency?(value["dependency"]) and intent?(value)
  end

  def valid?(_value), do: false

  @spec timeline?(value :: term()) :: boolean()
  def timeline?(nil), do: true

  def timeline?(
        %{"format" => 1, "schedules" => schedules, "next" => next, "condition" => condition} =
          value
      )
      when map_size(value) == 4 and is_map(schedules) and is_map(next) do
    map_size(schedules) <= 16 and Enum.sort(Map.keys(schedules)) == Enum.sort(Map.keys(next)) and
      condition in ~w(normal harsh closed) and
      Enum.all?(schedules, &cursor?(&1, next))
  end

  def timeline?(_value), do: false

  defp timing?(value),
    do:
      coordinate?(value["first_at"]) and recurrence?(value["every"]) and
        (is_nil(value["until"]) or
           (coordinate?(value["until"]) and value["until"] >= value["first_at"]))

  defp cursor?({id, row}, next),
    do:
      Scope.id?(id) and valid?(row) and
        (is_nil(next[id]) or (coordinate?(next[id]) and next[id] >= row["first_at"]))

  @spec intent(schedule :: map()) :: map()
  def intent(row) do
    intent = %{type: row["action"], target_id: row["target_id"]}

    if row["action"] in ~w(produce disrupt offer),
      do: Map.put(intent, :quantity, row["quantity"]),
      else: intent
  end

  @spec actor?(state :: map(), schedule :: map()) :: boolean()
  def actor?(_state, %{"action" => "condition"}), do: true

  def actor?(state, row),
    do: match?(%{kind: :npc, alive: true, retired: false}, state.actors[row["actor_id"]])

  defp intent?(%{"action" => "condition", "condition" => condition}),
    do: condition in ~w(normal harsh closed)

  defp intent?(row),
    do:
      row["action"] in ~w(produce rest disrupt offer adjudicate) and Scope.id?(row["actor_id"]) and
        LocalAction.valid_intent?(intent(row))

  defp coordinate?(value),
    do: is_integer(value) and value in -9_000_000_000_000..9_000_000_000_000

  defp recurrence?(nil), do: true

  defp recurrence?(%{"unit" => unit, "value" => value} = amount),
    do:
      map_size(amount) == 2 and unit in ~w(second minute hour day month year) and
        is_integer(value) and value in 1..31_622_400

  defp recurrence?(_value), do: false
  defp availability?(nil), do: true

  defp availability?(%{"from" => first, "to" => last} = span),
    do: map_size(span) == 2 and coordinate?(first) and coordinate?(last) and first < last

  defp availability?(_value), do: false
  defp dependency?(nil), do: true

  defp dependency?(%{"zone_id" => zone, "condition" => condition} = value),
    do: map_size(value) == 2 and Scope.id?(zone) and condition in ~w(normal harsh closed)

  defp dependency?(_value), do: false
end
