defmodule Genesis.Repo.Migrations.AddWorldNetworks do
  use Ecto.Migration

  def change do
    create table(:world_networks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :generation, :bigint, null: false
      add :revision, :bigint, null: false
      add :data, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:world_networks, [:world_id, :generation])

    create constraint(:world_networks, :valid_network_counters,
             check: "generation >= 0 AND revision > 0"
           )
  end
end
