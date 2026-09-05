defmodule Genesis.Repo.Migrations.AddWorldCalendarMapping do
  use Ecto.Migration

  def change do
    alter table(:worlds) do
      add :calendar, :map, null: false, default: %{}
    end
  end
end
