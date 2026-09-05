defmodule Genesis.Persistence.Event do
  @moduledoc "Stored world events; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "world_events" do
    field :world_id, :binary_id
    field :cursor, :integer
    field :snapshot_id, :binary_id
    field :scope_key, :string
    field :kind, :string
    field :campaign_id, :binary_id
    field :experience_id, :binary_id
    field :principal_id, :binary_id
    field :actor_id, :string
    field :core_event_id, :string
    field :event, :map
    field :transition, :map, default: %{}
    field :audience_users, {:array, :binary_id}, default: []
    field :source_event_id, :binary_id
    field :recorded_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
