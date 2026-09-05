defmodule Genesis.Persistence.GlobalDependency do
  @moduledoc "Exclusive scoped global write with pinned published-state and jurisdiction reads."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "global_dependencies" do
    field :world_id, :binary_id
    field :experience_id, :binary_id
    field :generation, :integer
    field :resource_id, :string
    field :mode, :string
    field :base_digest, :string
    field :network_revision, :integer
    timestamps(type: :utc_datetime_usec)
  end
end
