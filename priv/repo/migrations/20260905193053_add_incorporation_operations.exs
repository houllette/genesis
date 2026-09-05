defmodule Genesis.Repo.Migrations.AddIncorporationOperations do
  use Ecto.Migration

  def change do
    create table(:incorporation_operations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false

      add :experience_id, references(:experiences, type: :binary_id, on_delete: :delete_all),
        null: false

      add :principal_id, references(:users, type: :binary_id), null: false
      add :generation, :bigint, null: false
      add :preview_id, :text, null: false
      add :request_id, :text, null: false
      add :status, :text, null: false
      add :manifest, :map, null: false
      add :result, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:incorporation_operations, [:world_id, :principal_id, :request_id])

    create unique_index(:incorporation_operations, [:world_id],
             where: "status IN ('prepared', 'committed')",
             name: :one_active_incorporation
           )

    create constraint(:incorporation_operations, :valid_incorporation_status,
             check: "status IN ('prepared', 'committed', 'installed', 'aborted')"
           )
  end
end
