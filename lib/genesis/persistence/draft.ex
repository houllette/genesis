defmodule Genesis.Persistence.Draft do
  @moduledoc "Stored content drafts; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "content_drafts" do
    field :world_id, :binary_id
    field :zone_id, :string
    field :entity_id, :string
    field :kind, :string
    field :attrs, :map
    field :base_revision, :integer
    field :author_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end
end
