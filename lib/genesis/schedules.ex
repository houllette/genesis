defmodule Genesis.Schedules do
  @moduledoc "Typed native schedule form boundary. Curation still validates rules, resources, revision and authority."
  alias Genesis.Content

  @spec create(
          scope :: term(),
          world :: String.t(),
          zone :: String.t(),
          revision :: integer(),
          fields :: map(),
          request :: String.t()
        ) :: term()
  def create(scope, world, zone, revision, fields, request) do
    with {:ok, attrs} <- attributes(fields),
         do: Content.curate(scope, world, zone, revision, nil, attrs, request)
  end

  @spec attributes(fields :: term()) :: term()
  def attributes(fields) when is_map(fields) do
    with true <-
           Map.keys(fields) --
             ~w(name action actor_id target_id quantity first_at every_value every_unit condition) ==
             [],
         {:ok, first} <- integer(fields["first_at"]),
         {:ok, every} <- recurrence(fields),
         {:ok, attrs} <- action(fields) do
      {:ok,
       Map.merge(attrs, %{
         "kind" => "schedule",
         "name" => fields["name"],
         "version" => 1,
         "first_at" => first,
         "every" => every
       })}
    else
      _ -> {:error, :invalid_schedule}
    end
  end

  def attributes(_fields), do: {:error, :invalid_schedule}

  defp action(%{"action" => "condition", "condition" => condition}),
    do: {:ok, %{"action" => "condition", "condition" => condition}}

  defp action(%{"action" => action} = fields)
       when action in ~w(produce rest disrupt offer adjudicate) do
    attrs = Map.take(fields, ~w(action actor_id target_id))

    if action in ~w(produce disrupt offer) do
      with {:ok, quantity} <- integer(fields["quantity"]),
           do: {:ok, Map.put(attrs, "quantity", quantity)}
    else
      {:ok, attrs}
    end
  end

  defp action(_fields), do: {:error, :invalid_schedule}
  defp recurrence(%{"every_value" => value}) when value in [nil, "", "0"], do: {:ok, nil}

  defp recurrence(fields) do
    with {:ok, value} <- integer(fields["every_value"]),
         do: {:ok, %{"unit" => fields["every_unit"], "value" => value}}
  end

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, :invalid_schedule}
    end
  end

  defp integer(_value), do: {:error, :invalid_schedule}
end
