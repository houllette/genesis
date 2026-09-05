defmodule Genesis.Persistence.Gathering do
  @moduledoc "Stored experience gatherings; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "experience_gatherings" do
    field :world_id, :binary_id
    field :experience_id, :binary_id
    field :request_id, :string
    field :title, :string
    field :starts_at, :utc_datetime_usec
    field :meeting_url, :string
    timestamps(type: :utc_datetime_usec)
  end
end
