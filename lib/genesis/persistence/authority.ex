defmodule Genesis.Persistence.Authority do
  @moduledoc "Durable actor bindings and current permissions; no role is accepted from an action payload."
  import Ecto.Query
  alias Genesis.Accounts.{Scope, User}
  alias Genesis.Core.Audience
  alias Genesis.Experiences

  alias Genesis.Persistence.{
    Access,
    Binding,
    CampaignMember,
    Footprints,
    Snapshot,
    Snapshots,
    WorldMember
  }

  alias Genesis.Repo

  @spec principal(
          scope :: term(),
          world_id :: String.t(),
          experience_id :: String.t(),
          actor_id :: String.t() | nil
        ) :: {:ok, map(), Snapshot.t()} | {:error, atom()}
  def principal(scope, world, experience, actor) do
    with {:ok, exp} <- Experiences.get(scope, world, experience),
         true <- exp.status in ["active", "paused", "ready"],
         {:ok, user} <- Access.user_id(scope),
         {:ok, snapshot} <- Footprints.actor_snapshot(exp, actor),
         {:ok, state} <- Snapshots.load(snapshot),
         {:ok, role} <- role(scope, exp, user, actor, state) do
      {:ok,
       %{
         id: user,
         user_id: user,
         campaign_id: exp.campaign_id,
         actor_id: actor,
         role: role,
         scope: state.scope,
         zone_id: state.zone_id,
         snapshot_id: snapshot.id,
         status: if(exp.status == "active", do: :active, else: :paused)
       }, snapshot}
    else
      _ -> {:error, :unauthorized}
    end
  end

  @spec current(principal :: map()) :: {:ok, map()} | {:error, atom()}
  def current(principal) do
    scope = Scope.for_user(Repo.get(User, principal.user_id))

    with {:ok, current, _snapshot} <-
           principal(scope, principal.scope.world_id, principal.scope.id, principal.actor_id),
         true <-
           current.scope == principal.scope and current.campaign_id == principal.campaign_id and
             current.role == principal.role do
      {:ok, current}
    else
      _ -> {:error, :unauthorized}
    end
  end

  @spec audience_users(principal :: map(), effect :: map()) :: [String.t()]
  def audience_users(principal, effect) do
    members =
      Repo.all(
        from m in CampaignMember,
          join: w in WorldMember,
          on: w.world_id == m.world_id and w.user_id == m.user_id,
          where:
            m.campaign_id == ^principal.campaign_id and is_nil(m.revoked_at) and
              is_nil(w.revoked_at)
      )

    bindings = Repo.all(from b in Binding, where: b.campaign_id == ^principal.campaign_id)

    recipients =
      members
      |> Enum.filter(fn member ->
        actor =
          Enum.find_value(bindings, fn b -> if b.user_id == member.user_id, do: b.actor_id end)

        viewer = %{role: if(member.role == "gm", do: :gm, else: :player), actor_id: actor}
        Audience.permits?(effect.audience, viewer)
      end)
      |> Enum.map(& &1.user_id)

    stewards =
      Repo.all(
        from w in WorldMember,
          where:
            w.world_id == ^principal.scope.world_id and w.role == "steward" and
              is_nil(w.revoked_at),
          select: w.user_id
      )

    (recipients ++ stewards)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp role(scope, exp, user, actor, state) do
    member = Repo.get_by(CampaignMember, campaign_id: exp.campaign_id, user_id: user)

    gm =
      Access.world(scope, exp.world_id, ["steward"]) == :ok or
        match?(%{role: "gm", revoked_at: nil}, member)

    binding =
      Repo.get_by(Binding,
        world_id: exp.world_id,
        campaign_id: exp.campaign_id,
        user_id: user,
        actor_id: actor || ""
      )

    select_role(gm, member, binding, actor, state, exp.participants)
  end

  defp select_role(true, _member, binding, actor, state, _participants) do
    if is_nil(actor) or match?(%{kind: :npc}, state.actors[actor]) or not is_nil(binding),
      do: {:ok, :gm},
      else: {:error, :unauthorized}
  end

  defp select_role(
         false,
         %{role: "player", revoked_at: nil},
         binding,
         actor,
         _state,
         participants
       )
       when not is_nil(binding) do
    if actor in participants, do: {:ok, :player}, else: {:error, :unauthorized}
  end

  defp select_role(
         false,
         %{role: "spectator", revoked_at: nil},
         _binding,
         nil,
         _state,
         _participants
       ),
       do: {:ok, :spectator}

  defp select_role(_gm, _member, _binding, _actor, _state, _participants),
    do: {:error, :unauthorized}
end
