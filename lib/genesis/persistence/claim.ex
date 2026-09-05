defmodule Genesis.Persistence.Claim do
  @moduledoc "Stored experience claims; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "experience_claims" do
    field :world_id, :binary_id
    field :generation, :integer
    field :resource_kind, :string
    field :resource_id, :string
    field :experience_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end
end
