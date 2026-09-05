defmodule Genesis.Repo.Migrations.AddWorldAtlasRecords do
  use Ecto.Migration

  def change do
    create table(:atlas_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :generation, :bigint, null: false
      add :kind, :string, null: false
      add :visibility, :string, null: false
      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :restrict)
      add :revision, :bigint, null: false
      add :archived, :boolean, null: false, default: false
      add :data, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:atlas_records, [:world_id, :generation, :visibility, :campaign_id])
    create constraint(:atlas_records, :atlas_revision_positive, check: "revision > 0")

    create constraint(:atlas_records, :atlas_audience,
             check:
               "(visibility IN ('public', 'gm') AND campaign_id IS NULL) OR (visibility = 'party' AND campaign_id IS NOT NULL)"
           )
  end
end
