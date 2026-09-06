defmodule Genesis.Repo.Migrations.AddTimelinePreparations do
  use Ecto.Migration

  def change do
    alter table(:experiences) do
      add :start_offset, :bigint, null: false, default: 0
    end

    create constraint(:experiences, :bounded_start_offset,
             check: "start_offset >= 0 AND start_offset <= 31622400"
           )

    alter table(:incorporation_operations) do
      modify :experience_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    drop index(:advancement_windows, [:world_id], name: :one_open_window_per_world)

    create unique_index(:advancement_windows, [:world_id],
             where: "status <> 'closed'",
             name: :one_open_window_per_world
           )

    create table(:timeline_preparations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false

      add :window_id, references(:advancement_windows, type: :binary_id, on_delete: :restrict),
        null: false

      add :principal_id, references(:users, type: :binary_id), null: false
      add :generation, :bigint, null: false
      add :base_revision, :bigint, null: false
      add :request_id, :text, null: false
      add :status, :text, null: false
      add :input, :map, null: false
      add :manifest, :map, null: false
      add :work, :map, null: false
      add :digest, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:timeline_preparations, [:world_id, :principal_id, :request_id])

    create unique_index(:timeline_preparations, [:window_id],
             where: "status IN ('preparing', 'ready', 'needs_review')",
             name: :one_active_timeline_preparation
           )

    create constraint(:timeline_preparations, :valid_timeline_status,
             check: "status IN ('preparing', 'ready', 'needs_review', 'cancelled', 'published')"
           )
  end
end
