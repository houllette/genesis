defmodule Genesis.Persistence.History do
  @moduledoc "Commit-ordered, audience-frozen history and deterministic authorized away digests."
  import Ecto.Query
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
