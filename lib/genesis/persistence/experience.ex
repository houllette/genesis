defmodule Genesis.Persistence.Experience do
  @moduledoc "Stored experiences; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "experiences" do
    field :world_id, :binary_id
    field :campaign_id, :binary_id
    field :window_id, :binary_id
    field :zone_id, :string
    field :name, :string
    field :status, :string, default: "draft"
    field :revision, :integer, default: 0
    field :participants, {:array, :string}, default: []
    field :base_checkpoint_id, :binary_id
    field :deadline, :map, default: %{}
    field :completion, :map, default: %{}
    field :start_offset, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end
