defmodule Genesis.Persistence.TransferRecovery do
  @moduledoc "Checks durable evidence before releasing transfer fences. Call under the World transaction lock."
  import Ecto.Query
  alias Genesis.Persistence.Codec
  alias Genesis.Persistence.Event
  alias Genesis.Persistence.Reservation
  alias Genesis.Persistence.Snapshot
  alias Genesis.Persistence.Snapshots
  alias Genesis.Persistence.Transfers
  alias Genesis.Repo

  @spec verify(world :: map(), operation :: map()) :: :ok | {:error, :corrupt_transfer}
  def verify(world, op) do
    with true <- world.id == op.world_id and world.generation == op.generation,
         {:ok, {_campaign, actor, token}} <- Codec.load(op.payload),
         true <- actor == op.actor_id and Transfers.valid_token?(token),
         true <- token["generation"] == op.generation,
         true <- op.source_snapshot_id != op.destination_snapshot_id,
         true <-
           Repo.aggregate(from(r in Reservation, where: r.transfer_id == ^op.id), :count) == 2,
         :ok <- side(op, token, "source", "from", "departed"),
         :ok <- side(op, token, "destination", "to", "arrived"),
         true <- receipt?(op, token) do
      :ok
    else
      _ -> {:error, :corrupt_transfer}
    end
  end

  defp side(op, token, name, place, direction) do
    id = if name == "source", do: op.source_snapshot_id, else: op.destination_snapshot_id
    revision = token[name <> "_revision"]

    with %Snapshot{} = row <- Repo.get(Snapshot, id),
         true <- row.world_id == op.world_id and row.generation == op.generation,
         true <- row.scope_kind == "experience" and row.experience_id == op.experience_id,
         true <- row.zone_id == token[place],
         %{transfer_id: transfer, revision: ^revision} <- Repo.get(Reservation, id),
         true <- transfer == op.id,
         {:ok, _} <- Snapshots.load(row),
         true <- side_evidence?(op, row, name, direction, revision) do
      :ok
    else
      _ -> {:error, :corrupt_transfer}
    end
  end

  defp side_evidence?(%{status: "prepared"} = op, row, name, _direction, revision) do
    # Earlier Phase 07 prepares have no digest fields. They still require the
    # original reserved revision and a structurally valid, digest-checked snapshot.
    row.revision == revision and
      Map.get(op.result, name <> "_digest", row.digest) == row.digest
  end

  defp side_evidence?(%{status: "committed"} = op, row, _name, direction, revision) do
    case Repo.get_by(Event, world_id: op.world_id, core_event_id: op.id <> "/" <> direction) do
      nil ->
        false

      event ->
        row.revision == revision + 1 and event.snapshot_id == row.id and
          event.experience_id == op.experience_id and event.actor_id == op.actor_id and
          event.kind == "experience" and event.id in Map.get(op.result, "event_ids", []) and
          event.transition["after"] == row.digest
    end
  end

  defp side_evidence?(_op, _row, _name, _direction, _revision), do: false

  defp receipt?(%{status: "prepared"}, _token), do: true

  defp receipt?(op, token) do
    result = op.result

    directions =
      if token["exchange"], do: ["departed", "arrived", "exchange"], else: ["departed", "arrived"]

    expected = Enum.map(directions, &event_id(op, &1))

    result["id"] == op.id and result["actor_id"] == op.actor_id and
      result["from"] == token["from"] and result["to"] == token["to"] and
      result["source_revision"] == token["source_revision"] + 1 and
      result["destination_revision"] == token["destination_revision"] + 1 and
      nil not in expected and result["event_ids"] == expected
  end

  defp event_id(op, direction) do
    case Repo.get_by(Event, world_id: op.world_id, core_event_id: op.id <> "/" <> direction) do
      nil -> nil
      event -> event.id
    end
  end
end
