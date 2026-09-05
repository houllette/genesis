defmodule Genesis.Persistence.Reservation do
  @moduledoc "A short durable fence on one scoped Zone snapshot."
  use Ecto.Schema
  @primary_key {:snapshot_id, :binary_id, autogenerate: false}
  schema "zone_reservations" do
    field :transfer_id, :binary_id
    field :revision, :integer
  end
end
