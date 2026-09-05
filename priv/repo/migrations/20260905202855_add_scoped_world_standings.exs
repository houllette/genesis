defmodule Genesis.Repo.Migrations.AddScopedWorldStandings do
  use Ecto.Migration

  def change do
    create table(:world_standings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :experience_id, references(:experiences, type: :binary_id, on_delete: :delete_all)
      add :generation, :bigint, null: false
      add :scope_key, :text, null: false
      add :resource_id, :text, null: false
      add :institution_id, :text, null: false
      add :actor_id, :text, null: false
      add :base, :map, null: false
      add :data, :map, null: false
      add :digest, :text, null: false
      add :revision, :bigint, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:world_standings, [:world_id, :generation, :scope_key, :resource_id])

    create table(:global_dependencies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false

      add :experience_id, references(:experiences, type: :binary_id, on_delete: :delete_all),
        null: false

      add :generation, :bigint, null: false
      add :resource_id, :text, null: false
      add :mode, :text, null: false
      add :base_digest, :text, null: false
      add :network_revision, :bigint, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:global_dependencies, [:world_id, :generation, :resource_id])
    create constraint(:global_dependencies, :global_write_dependency, check: "mode = 'write'")
  end
end
