defmodule Genesis.Persistence.Preparation do
  @moduledoc "Durable, unpublished timeline proposal and bounded continuation. Not a second published snapshot."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "timeline_preparations" do
    field :world_id, :binary_id
    field :window_id, :binary_id
    field :principal_id, :binary_id
    field :generation, :integer
    field :base_revision, :integer
    field :request_id, :string
    field :status, :string
    field :input, :map
    field :manifest, :map
    field :work, :map
    field :digest, :string
    timestamps(type: :utc_datetime_usec)
  end
end
