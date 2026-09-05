defmodule Genesis.Persistence.Transfer do
  @moduledoc "Durable transfer decision and retry identity. Reservations are separate from Experience claims."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "zone_transfers" do
    field :world_id, :binary_id
    field :experience_id, :binary_id
    field :generation, :integer
    field :principal_id, :binary_id
    field :actor_id, :string
    field :source_snapshot_id, :binary_id
    field :destination_snapshot_id, :binary_id
    field :request_id, :string
    field :payload, :map
    field :status, :string
    field :result, :map
    timestamps(type: :utc_datetime_usec)
  end
end
