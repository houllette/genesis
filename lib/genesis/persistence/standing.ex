defmodule Genesis.Persistence.Standing do
  @moduledoc "World-owned published or Experience-local standing snapshot, never a second local institution."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "world_standings" do
    field :world_id, :binary_id
    field :experience_id, :binary_id
    field :generation, :integer
    field :scope_key, :string
    field :resource_id, :string
    field :institution_id, :string
    field :actor_id, :string
    field :base, :map
    field :data, :map
    field :digest, :string
    field :revision, :integer
    timestamps(type: :utc_datetime_usec)
  end
end
