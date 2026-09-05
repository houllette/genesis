defmodule Genesis.Persistence.Outbox do
  @moduledoc "Stored event outbox; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "event_outbox" do
    field :world_id, :binary_id
    field :event_id, :binary_id
    field :cursor, :integer
    field :delivered_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
