defmodule Genesis.Persistence.Access do
  @moduledoc "Current database membership is checked at every boundary, including receipt replay."
  import Ecto.Query
  alias Genesis.Accounts.Scope
  alias Genesis.Persistence.{Campaign, CampaignMember, WorldMember}
  alias Genesis.Repo

  @spec user_id(scope :: term()) :: {:ok, String.t()} | {:error, :unauthorized}
  def user_id(%Scope{user: %{id: id}}) when is_binary(id), do: {:ok, id}
  def user_id(_scope), do: {:error, :unauthorized}

  @spec uuid?(value :: term()) :: boolean()
  def uuid?(value), do: match?({:ok, _id}, Ecto.UUID.cast(value))

  @spec world(scope :: term(), world_id :: String.t(), roles :: [String.t()]) ::
          :ok | {:error, atom()}
  def world(scope, world_id, roles \\ ["steward", "builder", "viewer"]) do
    with {:ok, user} <- user_id(scope),
         true <- uuid?(world_id),
         %WorldMember{role: role, revoked_at: nil} <-
           Repo.get_by(WorldMember, world_id: world_id, user_id: user),
         true <- role in roles do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  @spec campaign(
          scope :: term(),
          world_id :: String.t(),
          campaign_id :: String.t(),
          roles :: [String.t()]
        ) :: {:ok, Campaign.t()} | {:error, atom()}
  def campaign(scope, world_id, campaign_id, roles \\ ["gm", "player", "spectator"]) do
    with :ok <- world(scope, world_id),
         true <- uuid?(campaign_id),
         %Campaign{} = campaign <- Repo.get_by(Campaign, id: campaign_id, world_id: world_id),
         {:ok, user} <- user_id(scope) do
      permitted =
        Repo.exists?(
          from m in CampaignMember,
            where:
              m.campaign_id == ^campaign.id and m.user_id == ^user and m.role in ^roles and
                is_nil(m.revoked_at)
        )

      if permitted or world(scope, world_id, ["steward"]) == :ok,
        do: {:ok, campaign},
        else: {:error, :unauthorized}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :unavailable}
    end
  end
end
