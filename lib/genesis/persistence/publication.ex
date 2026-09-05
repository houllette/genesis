defmodule Genesis.Persistence.Publication do
  @moduledoc "Durable publication identity and world-wide admission/read fence until cache installation."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "incorporation_operations" do
    field :world_id, :binary_id
    field :experience_id, :binary_id
    field :principal_id, :binary_id
    field :generation, :integer
    field :preview_id, :string
    field :request_id, :string
    field :status, :string
    field :manifest, :map
    field :result, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
