defmodule Genesis.Content.AtlasEntry do
  @moduledoc "World-owned descriptive atlas records. Runtime people, places, items and institutions are references, never copied here."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  @type t :: %__MODULE__{}
  schema "atlas_records" do
    field :world_id, :binary_id
    field :generation, :integer
    field :kind, :string
    field :visibility, :string
    field :campaign_id, :binary_id
    field :revision, :integer
    field :archived, :boolean, default: false
    field :data, :map
    timestamps(type: :utc_datetime_usec)
  end
end
