defmodule Genesis.Persistence.Snapshot do
  @moduledoc "Stored zone snapshots; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "zone_snapshots" do
    field :world_id, :binary_id
    field :generation, :integer
    field :scope_key, :string
    field :scope_kind, :string
    field :experience_id, :binary_id
    field :base_checkpoint_id, :binary_id
    field :zone_id, :string
    field :revision, :integer
    field :state, :map
    field :digest, :string
    timestamps(type: :utc_datetime_usec)
  end
end
