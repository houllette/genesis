defmodule Genesis.Campaigns do
  @moduledoc "Campaign membership and organization, never an alternative game-state writer."
  import Ecto.Query
  alias Genesis.Accounts.User
  alias Genesis.Core.Scope

  alias Genesis.Persistence.{
    Access,
    Binding,
    Campaign,
    CampaignMember,
    Claim,
    Codec,
    Entity,
    Experience,
    Tx,
    WorldMember
  }

  alias Genesis.Repo
  alias Genesis.Time.Clock

  @spec create_campaign(
          scope :: term(),
          world_id :: String.t(),
          attrs :: map(),
          request_id :: String.t()
        ) :: {:ok, map()} | {:error, term()}
  def create_campaign(scope, world_id, attrs, request) do
    Tx.run(world_id, fn world ->
      with :ok <- Access.world(scope, world_id, ["steward", "builder"]),
           {:ok, user} <- Access.user_id(scope),
           true <-
             is_map(attrs) and map_size(attrs) == 1 and Scope.id?(attrs["name"]) and
               Scope.id?(request) do
        create_or_restore(world, user, attrs, request)
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_campaign}
      end
    end)
  end

  defp create_or_restore(world, user, attrs, request) do
    world_id = world.id

    case Tx.receipt(world_id, "campaigns", user, request, attrs) do
      {:ok, %{"campaign_id" => id}} ->
        {:ok, Repo.get!(Campaign, id)}

      :new ->
        campaign = Tx.insert!(Campaign, %{world_id: world_id, name: attrs["name"]})

        Tx.insert!(CampaignMember, %{
          world_id: world_id,
          campaign_id: campaign.id,
          user_id: user,
          role: "gm"
        })

        Tx.event!(world, %{
          scope_key: "campaigns",
          kind: "world",
          campaign_id: campaign.id,
          principal_id: user,
          audience_users: [user],
          event: Codec.dump!(%{type: "campaign_created", result: %{"name" => campaign.name}})
        })

        Tx.remember!(world_id, "campaigns", user, request, attrs, %{
          "campaign_id" => campaign.id
        })

        {:ok, campaign}

      error ->
        error
    end
  end

  @spec add_member(
          scope :: term(),
          world_id :: String.t(),
          campaign_id :: String.t(),
          user_id :: String.t(),
          role :: String.t()
        ) :: {:ok, map()} | {:error, term()}
  @spec add_member(
          scope :: term(),
          world :: String.t(),
          campaign :: String.t(),
          user :: String.t(),
          role :: String.t(),
          request :: String.t() | nil
        ) :: term()
  def add_member(scope, world_id, campaign_id, user, role, request \\ nil),
    do:
      command(
        scope,
        world_id,
        campaign_id,
        "campaign-roles",
        request,
        {campaign_id, user, role},
        CampaignMember,
        fn -> change_member(scope, world_id, campaign_id, user, role) end
      )

  defp change_member(scope, world_id, campaign_id, user, role) do
    Tx.run(world_id, fn world ->
      with {:ok, campaign} <- Access.campaign(scope, world_id, campaign_id, ["gm"]),
           false <- campaign.archived,
           true <- role in ["gm", "player", "spectator"],
           true <- Access.uuid?(user),
           %User{} <- Repo.get(User, user) do
        ensure_world_member(world_id, user)
        existing = Repo.get_by(CampaignMember, campaign_id: campaign_id, user_id: user)

        attrs = %{
          world_id: world_id,
          campaign_id: campaign_id,
          user_id: user,
          role: role,
          revoked_at: nil
        }

        member = upsert_member(existing, attrs)

        Tx.metadata!(
          world,
          scope,
          "campaign_role_changed",
          %{"user_id" => user, "role" => role},
          campaign_id
        )

        {:ok, member}
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_member}
      end
    end)
  end

  defp upsert_member(nil, attrs), do: Tx.insert!(CampaignMember, attrs)
  defp upsert_member(existing, attrs), do: Tx.update!(existing, attrs)

  @spec get_campaign(scope :: term(), world_id :: String.t(), campaign_id :: String.t()) ::
          {:ok, map()} | {:error, term()}
  def get_campaign(scope, world_id, campaign_id),
    do: Access.campaign(scope, world_id, campaign_id)

  @spec archive(
          scope :: term(),
          world_id :: String.t(),
          campaign_id :: String.t(),
          revision :: integer()
        ) :: {:ok, Campaign.t()} | {:error, term()}
  @spec archive(
          scope :: term(),
          world :: String.t(),
          campaign :: String.t(),
          revision :: integer(),
          request :: String.t() | nil
        ) :: term()
  def archive(scope, world, campaign, revision, request \\ nil),
    do:
      command(
        scope,
        world,
        campaign,
        "campaign-archive",
        request || "archive-#{campaign}-#{revision}",
        {campaign, revision},
        Campaign,
        fn -> archive_new(scope, world, campaign, revision) end
      )

  defp archive_new(scope, world, campaign, revision) do
    Tx.run(world, fn world_record ->
      with {:ok, record} <- Access.campaign(scope, world, campaign, ["gm"]),
           true <- record.revision == revision,
           false <-
             Repo.exists?(
               from e in Experience,
                 where:
                   e.campaign_id == ^campaign and
                     e.status not in ["incorporated", "closed_without_publication"]
             ) do
        Tx.metadata!(
          world_record,
          scope,
          "campaign_archived",
          %{"campaign_id" => campaign},
          campaign
        )

        {:ok, Tx.update!(record, %{archived: true, revision: revision + 1})}
      else
        {:error, _reason} = error -> error
        false -> {:error, :stale_revision}
        true -> {:error, :unfinished_experiences}
      end
    end)
  end

  @spec bind_character(
          scope :: term(),
          world_id :: String.t(),
          campaign_id :: String.t(),
          user_id :: String.t(),
          actor_id :: String.t()
        ) :: {:ok, Binding.t()} | {:error, term()}
  @spec bind_character(
          scope :: term(),
          world :: String.t(),
          campaign :: String.t(),
          user :: String.t(),
          actor :: String.t(),
          request :: String.t() | nil
        ) :: term()
  def bind_character(scope, world, campaign, user, actor, request \\ nil),
    do:
      command(
        scope,
        world,
        campaign,
        "character-binding",
        request,
        {campaign, user, actor},
        Binding,
        fn -> bind_new(scope, world, campaign, user, actor) end
      )

  defp bind_new(scope, world, campaign, user, actor) do
    Tx.run(world, fn world_record ->
      with {:ok, %{archived: false}} <- Access.campaign(scope, world, campaign, ["gm"]),
           true <- Access.uuid?(user) and Scope.id?(actor),
           %{revoked_at: nil} <- Repo.get_by(CampaignMember, campaign_id: campaign, user_id: user),
           %{actor_kind: "pc"} <-
             Repo.get_by(Entity, world_id: world, kind: "actor", entity_id: actor),
           false <-
             Repo.exists?(
               from c in Claim,
                 where:
                   c.world_id == ^world and c.resource_kind == "actor" and c.resource_id == ^actor
             ) do
        result = assign_binding(scope, world, campaign, user, actor)

        audit_binding(result, world_record, scope, user, actor, campaign)

        result
      else
        {:error, _reason} = error -> error
        true -> {:error, :claimed}
        _ -> {:error, :invalid_binding}
      end
    end)
  end

  defp audit_binding({:ok, _}, world, scope, user, actor, campaign),
    do:
      Tx.metadata!(
        world,
        scope,
        "character_assigned",
        %{"user_id" => user, "actor_id" => actor},
        campaign
      )

  defp audit_binding(_error, _world, _scope, _user, _actor, _campaign), do: :ok

  defp assign_binding(scope, world, campaign, user, actor) do
    case Repo.get_by(Binding, world_id: world, actor_id: actor) do
      nil ->
        {:ok,
         Tx.insert!(Binding, %{
           world_id: world,
           campaign_id: campaign,
           user_id: user,
           actor_id: actor
         })}

      %{campaign_id: ^campaign, user_id: ^user} = existing ->
        {:ok, existing}

      %{user_id: ^user} = existing ->
        with {:ok, _old} <- Access.campaign(scope, world, existing.campaign_id, ["gm"]),
             do: {:ok, Tx.update!(existing, %{campaign_id: campaign})}

      _ ->
        {:error, :already_bound}
    end
  end

  @spec revoke_member(
          scope :: term(),
          world_id :: String.t(),
          campaign_id :: String.t(),
          user_id :: String.t()
        ) :: {:ok, CampaignMember.t()} | {:error, term()}
  @spec revoke_member(
          scope :: term(),
          world :: String.t(),
          campaign :: String.t(),
          user :: String.t(),
          request :: String.t() | nil
        ) :: term()
  def revoke_member(scope, world, campaign, user, request \\ nil),
    do:
      command(
        scope,
        world,
        campaign,
        "campaign-revoke",
        request,
        {campaign, user},
        CampaignMember,
        fn -> revoke_new(scope, world, campaign, user) end
      )

  defp revoke_new(scope, world, campaign, user) do
    Tx.run(world, fn record ->
      with {:ok, _campaign} <- Access.campaign(scope, world, campaign, ["gm"]),
           true <- Access.uuid?(user),
           %CampaignMember{} = member <-
             Repo.get_by(CampaignMember, campaign_id: campaign, user_id: user),
           {:ok, operator} <- Access.user_id(scope) do
        result = Tx.update!(member, %{revoked_at: Clock.read().utc})

        Tx.event!(record, %{
          scope_key: "campaigns",
          kind: "world",
          campaign_id: campaign,
          principal_id: operator,
          audience_users: [operator],
          event: Codec.dump!(%{type: "member_revoked", result: %{"user_id" => user}})
        })

        {:ok, result}
      else
        {:error, _reason} = error -> error
        _ -> {:error, :unavailable}
      end
    end)
  end

  @spec list_campaigns(scope :: term(), world_id :: String.t()) :: [Campaign.t()]
  def list_campaigns(scope, world_id) do
    if Access.world(scope, world_id) == :ok do
      Repo.all(from c in Campaign, where: c.world_id == ^world_id, order_by: c.name)
      |> Enum.filter(&match?({:ok, _campaign}, Access.campaign(scope, world_id, &1.id)))
    else
      []
    end
  end

  @doc false
  @spec ensure_world_member(world_id :: String.t(), user_id :: String.t()) :: WorldMember.t()
  def ensure_world_member(world_id, user) do
    Repo.get_by(WorldMember, world_id: world_id, user_id: user) ||
      Tx.insert!(WorldMember, %{world_id: world_id, user_id: user, role: "viewer"})
  end

  defp command(scope, world, campaign, key, request, payload, schema, fun) do
    Tx.run(world, fn _world ->
      with {:ok, _campaign} <- Access.campaign(scope, world, campaign, ["gm"]),
           {:ok, user} <- Access.user_id(scope) do
        Tx.record_command(world, user, key, request, payload, schema, fun)
      end
    end)
  end
end
