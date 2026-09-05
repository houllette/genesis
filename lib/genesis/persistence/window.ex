defmodule Genesis.Persistence.Window do
  @moduledoc "Stored advancement windows; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "advancement_windows" do
    field :world_id, :binary_id
    field :generation, :integer
    field :base_revision, :integer
    field :status, :string, default: "open"
    timestamps(type: :utc_datetime_usec)
  end
end
