defmodule Genesis.Persistence.Receipt do
  @moduledoc "Stored request receipts; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "request_receipts" do
    field :world_id, :binary_id
    field :scope_key, :string
    field :principal_id, :binary_id
    field :request_id, :string
    field :payload, :map
    field :result, :map
    timestamps(type: :utc_datetime_usec)
  end
end
