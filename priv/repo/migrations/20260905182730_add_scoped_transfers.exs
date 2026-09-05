defmodule Genesis.Repo.Migrations.AddScopedTransfers do
  use Ecto.Migration

  def up do
    alter table(:zone_snapshots) do
      add :base_checkpoint_id,
          references(:zone_checkpoints, type: :binary_id, on_delete: :nilify_all)
    end

    execute """
    UPDATE zone_snapshots AS s SET base_checkpoint_id = e.base_checkpoint_id
    FROM experiences AS e WHERE s.experience_id = e.id AND s.zone_id = e.zone_id
    """

    create table(:zone_transfers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false

      add :experience_id, references(:experiences, type: :binary_id, on_delete: :delete_all),
        null: false

      add :generation, :bigint, null: false
      add :principal_id, references(:users, type: :binary_id), null: false
      add :actor_id, :text, null: false

      add :source_snapshot_id,
          references(:zone_snapshots, type: :binary_id, on_delete: :delete_all), null: false

      add :destination_snapshot_id,
          references(:zone_snapshots, type: :binary_id, on_delete: :delete_all), null: false

      add :request_id, :text, null: false
      add :payload, :map, null: false
      add :status, :text, null: false
      add :result, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:zone_transfers, [
             :world_id,
             :generation,
             :experience_id,
             :principal_id,
             :request_id
           ])

    create constraint(:zone_transfers, :valid_transfer_status,
             check: "status IN ('prepared', 'committed', 'installed', 'aborted')"
           )

    create table(:zone_reservations, primary_key: false) do
      add :snapshot_id, references(:zone_snapshots, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :transfer_id, references(:zone_transfers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :revision, :bigint, null: false
    end
  end

  def down do
    drop table(:zone_reservations)
    drop table(:zone_transfers)
    alter table(:zone_snapshots), do: remove(:base_checkpoint_id)
  end
end
