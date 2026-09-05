defmodule Genesis.Persistence.Network do
  @moduledoc "A versioned global snapshot per World generation; local entities remain in Zone snapshots."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "world_networks" do
    field :world_id, :binary_id
    field :generation, :integer
    field :revision, :integer
    field :data, :map
    timestamps(type: :utc_datetime_usec)
  end
end
