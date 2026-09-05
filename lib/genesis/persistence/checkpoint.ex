defmodule Genesis.Persistence.Checkpoint do
  @moduledoc "Stored zone checkpoints; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "zone_checkpoints" do
    field :world_id, :binary_id
    field :snapshot_id, :binary_id
    field :cursor, :integer
    field :state, :map
    field :digest, :string
    timestamps(type: :utc_datetime_usec)
  end
end
