defmodule Genesis.Repo.Migrations.AddMembershipRevocation do
  use Ecto.Migration

  def change do
    alter table(:world_memberships) do
      add :revoked_at, :utc_datetime_usec
    end

    alter table(:campaign_memberships) do
      add :revoked_at, :utc_datetime_usec
    end
  end
end
