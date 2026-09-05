defmodule Genesis.Persistence.Replay do
  @moduledoc "Checkpoint plus recorded transitions, with digests and versions checked before accepting recovery."
  import Ecto.Query

  alias Genesis.Persistence.{
    Access,
    Checkpoint,
    Codec,
    Event,
    Snapshot,
    Snapshots,
    Transition,
    Tx
  }

  alias Genesis.Repo

  @spec restore(scope :: term(), world_id :: String.t(), checkpoint_id :: String.t()) ::
          {:ok, map()} | {:error, term()}
  def restore(scope, world, checkpoint) do
    Tx.run(world, fn record ->
      with :ok <- Access.world(scope, world, ["steward", "builder"]),
           true <- Access.uuid?(checkpoint),
           %Checkpoint{world_id: ^world} = checkpoint <- Repo.get(Checkpoint, checkpoint),
           {:ok, initial} <- Codec.load_state(checkpoint.state),
           true <- Codec.digest(initial) == checkpoint.digest,
           :ok <- Snapshots.compatible(record, initial),
           {:ok, replayed} <- replay_events(checkpoint, initial),
           %Snapshot{} = snapshot <- Repo.get(Snapshot, checkpoint.snapshot_id),
           true <- Codec.digest(replayed) == snapshot.digest do
        {:ok, replayed}
      else
        {:error, _reason} = error -> error
        _ -> {:error, :corrupt_history}
      end
    end)
  end

  defp replay_events(checkpoint, initial) do
    Repo.all(
      from e in Event,
        where: e.snapshot_id == ^checkpoint.snapshot_id and e.cursor > ^checkpoint.cursor,
        order_by: e.cursor
    )
    |> Enum.reduce_while({:ok, initial}, fn event, {:ok, state} ->
      result =
        if event.transition == %{} and is_nil(event.actor_id),
          do: {:ok, state},
          else: Transition.apply(state, event.transition)

      case result do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end
end
