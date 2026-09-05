defmodule Genesis.Persistence.World do
  @moduledoc "Stored worlds; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "worlds" do
    field :name, :string
    field :creator_id, :binary_id
    field :generation, :integer, default: 0
    field :revision, :integer, default: 0
    field :cursor, :integer, default: 0
    field :bundle, :map
    field :profile, :string, default: "village"
    field :calendar_id, :string, default: "ordinal"
    field :calendar_version, :integer, default: 1
    field :fictional_time, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end
