defmodule Genesis.Persistence.History do
  @moduledoc "Commit-ordered, audience-frozen history and deterministic authorized away digests."
  import Ecto.Query
  alias Genesis.Core.Scope
  alias Genesis.Experiences
  alias Genesis.Persistence.{Access, Codec, Event, Tx}
  alias Genesis.Repo

  @spec page(scope :: term(), world_id :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def page(scope, world_id, opts \\ []) do
    Tx.run(world_id, fn world ->
      with :ok <- Access.world(scope, world_id),
           {:ok, user} <- Access.user_id(scope),
           :ok <- permitted_scope(scope, world_id, Keyword.get(opts, :experience_id)),
           {:ok, after_cursor, limit} <- pagination(opts) do
        query =
          from e in Event,
            where:
              e.world_id == ^world_id and e.cursor > ^after_cursor and
                e.cursor <= ^world.cursor and ^user in e.audience_users,
            order_by: e.cursor,
            limit: ^limit

        events = query |> event_scope(Keyword.get(opts, :experience_id)) |> Repo.all()
        next = next_cursor(events, limit, max(after_cursor, world.cursor))

        {:ok, %{events: Enum.map(events, &project/1), next_cursor: next}}
      end
    end)
  end

  defp pagination(opts) do
    after_cursor = Keyword.get(opts, :after, 0)
    limit = Keyword.get(opts, :limit, 30)

    if is_integer(after_cursor) and after_cursor >= 0 and is_integer(limit) and limit in 1..100,
      do: {:ok, after_cursor, limit},
      else: {:error, :invalid_cursor}
  end

  @doc "Fetches a stable accepted-event identity with current scope and frozen-audience checks."
  @spec get(scope :: term(), world :: String.t(), id :: String.t()) :: term()
  def get(scope, world, id) do
    Tx.run(world, fn _ ->
      with true <- Access.uuid?(id),
           :ok <- Access.world(scope, world),
           {:ok, user} <- Access.user_id(scope),
           %Event{} = event <- Repo.get_by(Event, id: id, world_id: world),
           true <- user in event.audience_users,
           :ok <- event_access(scope, world, event) do
        {:ok, Map.put(project(event), :sources, source_links(scope, world, event, user))}
      else
        _ -> {:error, :unavailable}
      end
    end)
  end

  @spec source(scope :: term(), world :: String.t(), core_id :: String.t(), opts :: keyword()) ::
          term()
  def source(scope, world, core_id, opts \\ []) do
    Tx.run(world, fn _ ->
      with :ok <- Access.world(scope, world),
           {:ok, user} <- Access.user_id(scope),
           :ok <- permitted_scope(scope, world, Keyword.get(opts, :experience_id)),
           true <- Scope.id?(core_id) do
        query =
          from e in Event,
            where:
              e.world_id == ^world and e.core_event_id == ^core_id and ^user in e.audience_users,
            limit: 1

        query
        |> event_scope(Keyword.get(opts, :experience_id))
        |> Repo.one()
        |> source_result(scope, world)
      else
        _ -> {:error, :unavailable}
      end
    end)
  end

  defp source_result(nil, _scope, _world), do: {:error, :unavailable}
  defp source_result(event, scope, world), do: get(scope, world, event.id)

  defp event_access(scope, world, %{kind: "experience", experience_id: exp}),
    do: permitted_scope(scope, world, exp)

  defp event_access(_scope, _world, %{kind: "world"}), do: :ok
  defp event_access(_scope, _world, _event), do: {:error, :unavailable}

  defp source_links(scope, world, event, user) do
    {:ok, effect} = Codec.load(event.event)
    ids = Enum.take(Map.get(effect, :source_ids, []), 32)
    origins = Enum.reject([event.source_event_id], &is_nil/1)

    query =
      from e in Event,
        where:
          e.world_id == ^world and ^user in e.audience_users and
            (e.id in ^origins or e.core_event_id in ^ids),
        order_by: e.cursor,
        limit: 33

    Repo.all(query)
    |> Enum.filter(&(event_access(scope, world, &1) == :ok))
    |> Enum.map(&project/1)
  end

  defp event_scope(query, nil), do: from(e in query, where: e.kind == "world")

  defp event_scope(query, id),
    do: from(e in query, where: e.experience_id == ^id and e.kind == "experience")

  defp next_cursor(events, limit, fallback) do
    if length(events) == limit, do: List.last(events).cursor, else: fallback
  end

  @spec digest(scope :: term(), world_id :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def digest(scope, world, opts \\ []) do
    with {:ok, page} <- page(scope, world, opts) do
      {:ok,
       %{
         next_cursor: page.next_cursor,
         entries:
           Enum.map(page.events, fn event ->
             %{
               id: event.id,
               cursor: event.cursor,
               summary: event.type <> summary_suffix(event.result)
             }
           end)
       }}
    end
  end

  defp permitted_scope(_scope, _world, nil), do: :ok

  defp permitted_scope(scope, world, exp) do
    with {:ok, _experience} <- Experiences.get(scope, world, exp), do: :ok
  end

  defp project(record) do
    {:ok, event} = Codec.load(record.event)

    %{
      id: record.id,
      core_event_id: record.core_event_id,
      scope_kind: record.kind,
      experience_id: record.experience_id,
      cursor: record.cursor,
      recorded_at: record.recorded_at,
      type: event.type,
      result: Map.get(event, :result, %{}),
      occurred_at: Map.get(event, :occurred_at),
      actor_id: Map.get(event, :actor_id),
      target_id: Map.get(event, :target_id)
    }
  end

  defp summary_suffix(%{"outcome" => outcome}) when is_binary(outcome), do: ": " <> outcome
  defp summary_suffix(_result), do: ""
end
