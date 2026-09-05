defmodule Genesis.Invitations do
  @moduledoc "Explicit, email-bound campaign invitations. Sharing a link never grants world stewardship."
  alias Genesis.Accounts.{Scope, User}
  alias Genesis.Campaigns
  alias Genesis.Core.Scope, as: Identity
  alias Genesis.Persistence.{Access, Codec, Invitation, Tx}
  alias Genesis.Repo
  alias Genesis.Time.Clock
  alias Genesis.Worlds

  @spec invite(
          scope :: term(),
          world :: String.t(),
          campaign :: String.t(),
          attrs :: map(),
          request :: String.t()
        ) :: term()
  def invite(scope, world, campaign, attrs, request) do
    Tx.run(world, fn record ->
      with {:ok, %{archived: false}} <- Access.campaign(scope, world, campaign, ["gm"]),
           {:ok, user} <- Access.user_id(scope),
           true <- valid_attrs?(attrs) and Identity.id?(request) do
        create_or_restore(record, campaign, user, attrs, request)
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_invitation}
      end
    end)
  end

  defp create_or_restore(world, campaign, user, attrs, request) do
    payload = {campaign, attrs}

    case Tx.receipt(world.id, "invitations", user, request, payload) do
      {:ok, %{"invitation_id" => id}} ->
        {:ok, %{id: id, token: token(id)}}

      :new ->
        id = Worlds.named_id([world.id, user, request, "invitation"])

        invitation =
          Tx.insert!(Invitation, %{
            id: id,
            world_id: world.id,
            campaign_id: campaign,
            email: String.downcase(attrs["email"]),
            role: attrs["role"],
            inviter_id: user,
            token_hash: :crypto.hash(:sha256, token(id)),
            expires_at: DateTime.add(Clock.read().utc, 604_800, :second)
          })

        Tx.event!(world, %{
          scope_key: "invitations",
          kind: "world",
          campaign_id: campaign,
          principal_id: user,
          audience_users: [user],
          event:
            Codec.dump!(%{
              type: "invitation_created",
              result: %{"invitation_id" => invitation.id}
            })
        })

        Tx.remember!(world.id, "invitations", user, request, payload, %{"invitation_id" => id})
        {:ok, %{id: id, token: token(id)}}

      error ->
        error
    end
  end

  @spec accept(scope :: term(), token :: String.t()) :: term()
  def accept(scope, token) do
    with {:ok, invitation} <- lookup(token),
         {:ok, user} <- Access.user_id(scope) do
      Tx.run(invitation.world_id, fn world -> accept_locked(scope, world, invitation.id, user) end)
    end
  end

  defp accept_locked(scope, world, id, user) do
    invitation = Repo.get!(Invitation, id)
    inviter = Scope.for_user(Repo.get(User, invitation.inviter_id))

    with true <- String.downcase(scope.user.email) == invitation.email,
         true <-
           is_nil(invitation.accepted_at) and
             DateTime.before?(Clock.read().utc, invitation.expires_at),
         {:ok, _campaign} <- Access.campaign(inviter, world.id, invitation.campaign_id, ["gm"]),
         {:ok, _member} <-
           Campaigns.add_member(inviter, world.id, invitation.campaign_id, user, invitation.role) do
      Tx.update!(invitation, %{accepted_at: Clock.read().utc})

      Tx.event!(world, %{
        scope_key: "invitations",
        kind: "world",
        campaign_id: invitation.campaign_id,
        principal_id: user,
        audience_users: [user, invitation.inviter_id],
        event:
          Codec.dump!(%{
            type: "invitation_accepted",
            result: %{"campaign_id" => invitation.campaign_id}
          })
      })

      {:ok, %{world_id: world.id, campaign_id: invitation.campaign_id}}
    else
      _ -> {:error, :invalid_invitation}
    end
  end

  defp lookup(token) when is_binary(token) and byte_size(token) < 200 do
    with [id, _signature] <- String.split(token, ".", parts: 2),
         true <- Access.uuid?(id),
         %Invitation{} = invitation <- Repo.get(Invitation, id),
         true <- Plug.Crypto.secure_compare(invitation.token_hash, :crypto.hash(:sha256, token)) do
      {:ok, invitation}
    else
      _ -> {:error, :invalid_invitation}
    end
  end

  defp lookup(_token), do: {:error, :invalid_invitation}

  defp token(id) do
    secret =
      Application.fetch_env!(:genesis, GenesisWeb.Endpoint) |> Keyword.fetch!(:secret_key_base)

    signature = :crypto.mac(:hmac, :sha256, secret, "genesis:invitation:" <> id)
    id <> "." <> Base.url_encode64(signature, padding: false)
  end

  defp valid_attrs?(%{"email" => email, "role" => role} = attrs) do
    map_size(attrs) == 2 and is_binary(email) and byte_size(email) <= 160 and
      Regex.match?(~r/^[^\s@]+@[^\s@]+$/, email) and role in ~w(gm player spectator)
  end

  defp valid_attrs?(_attrs), do: false
end
