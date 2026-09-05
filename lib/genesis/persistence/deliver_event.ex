defmodule Genesis.Persistence.DeliverEvent do
  @moduledoc "At-least-once safe invalidation. Consumers reauthorize and fetch committed state."
  use Oban.Worker, queue: :default, max_attempts: 5
  alias Genesis.Persistence.{Outbox, Tx}
  alias Genesis.Repo
  alias Genesis.Time.Clock

  @impl true
  def perform(%Oban.Job{args: %{"outbox_id" => id}}) do
    case Repo.get(Outbox, id) do
      %{delivered_at: nil} = entry ->
        :ok =
          Phoenix.PubSub.broadcast(
            Genesis.PubSub,
            "world:#{entry.world_id}",
            {:world_changed, entry.world_id, entry.cursor}
          )

        Tx.update!(entry, %{delivered_at: Clock.read().utc})
        :ok

      _ ->
        :ok
    end
  end
end
