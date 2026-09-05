defmodule Genesis.Persistence.Entity do
  @moduledoc "Stored world entities; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "world_entities" do
    field :world_id, :binary_id
    field :kind, :string
    field :entity_id, :string
    field :zone_id, :string
    field :owner_kind, :string
    field :owner_id, :string
    field :actor_kind, :string
    timestamps(type: :utc_datetime_usec)
  end
end
