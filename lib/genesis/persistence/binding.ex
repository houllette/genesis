defmodule Genesis.Persistence.Binding do
  @moduledoc "Stored character bindings; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "character_bindings" do
    field :world_id, :binary_id
    field :campaign_id, :binary_id
    field :user_id, :binary_id
    field :actor_id, :string
    field :entity_kind, :string, default: "actor"
    timestamps(type: :utc_datetime_usec)
  end
end
