defmodule Genesis.Persistence.Note do
  @moduledoc "Stored workspace notes; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "workspace_notes" do
    field :world_id, :binary_id
    field :campaign_id, :binary_id
    field :entity_id, :string
    field :title, :string
    field :body, :string
    field :kind, :string, default: "note"
    field :visibility, :string, default: "private"
    field :author_id, :binary_id
    field :revision, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end
