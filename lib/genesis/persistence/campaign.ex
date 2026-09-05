defmodule Genesis.Persistence.Campaign do
  @moduledoc "Stored campaigns; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "campaigns" do
    field :world_id, :binary_id
    field :name, :string
    field :revision, :integer, default: 0
    field :archived, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end
end
