defmodule Genesis.Persistence.Invitation do
  @moduledoc "Stored workspace invitations; domain operations validate authority before changes."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  schema "workspace_invitations" do
    field :world_id, :binary_id
    field :campaign_id, :binary_id
    field :email, :string
    field :role, :string
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :inviter_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end
end
