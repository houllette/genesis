defmodule Genesis.Persistence.CampaignMember do
  @moduledoc "Stored campaign memberships; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "campaign_memberships" do
    field :revoked_at, :utc_datetime_usec
    field :world_id, :binary_id
    field :campaign_id, :binary_id
    field :user_id, :binary_id
    field :role, :string
    timestamps(type: :utc_datetime_usec)
  end
end
