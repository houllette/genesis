defmodule Genesis.Persistence.WorkspaceMetadataTest do
  use Genesis.DataCase, async: true
  alias Genesis.Accounts.Scope
  alias Genesis.{Campaigns, Experiences, Invitations}
  alias Genesis.Persistence.{Access, Authority, Binding, Invitation, Tx}
  alias Genesis.{Workspace, Worlds}
  import Genesis.AccountsFixtures
  import Genesis.WorldFixtures

  test "world stewards are occurrence-time GM recipients even for a builder-created campaign" do
    ctx = world_fixture()
    builder = Scope.for_user(user_fixture())
    {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, builder.user.id, "builder")

    {:ok, campaign} =
      Campaigns.create_campaign(
        builder,
        ctx.world.id,
        %{"name" => "Builder campaign"},
        "builder-campaign"
      )

    {:ok, exp} =
      Experiences.create(
        builder,
        ctx.world.id,
        campaign.id,
        %{"name" => "Bridge", "zone_id" => "bridge"},
        "builder-exp"
      )

    {:ok, _} = Experiences.start(builder, ctx.world.id, exp.id, 0)
    {:ok, principal, _} = Authority.principal(ctx.owner, ctx.world.id, exp.id, nil)

    assert Enum.sort(Authority.audience_users(principal, %{audience: :gm})) ==
             Enum.sort([ctx.owner.user.id, builder.user.id])
  end

  test "delayed role and binding retries return acknowledgements without restoring an older decision" do
    ctx = world_fixture()
    guest = Scope.for_user(user_fixture())

    assert {:ok, promoted} =
             Worlds.set_role(ctx.owner, ctx.world.id, guest.user.id, "builder", "promote")

    assert {:ok, _} = Worlds.set_role(ctx.owner, ctx.world.id, guest.user.id, "viewer", "demote")

    assert {:ok, ^promoted} =
             Worlds.set_role(ctx.owner, ctx.world.id, guest.user.id, "builder", "promote")

    assert {:error, :unauthorized} = Access.world(guest, ctx.world.id, ["builder"])

    assert {:error, :request_conflict} =
             Worlds.set_role(ctx.owner, ctx.world.id, guest.user.id, "steward", "promote")

    assert {:ok, original} =
             Campaigns.bind_character(
               ctx.owner,
               ctx.world.id,
               ctx.campaign.id,
               ctx.owner.user.id,
               "mara",
               "original"
             )

    {:ok, next} =
      Campaigns.create_campaign(ctx.owner, ctx.world.id, %{"name" => "Next campaign"}, "next")

    assert {:ok, reassigned} =
             Campaigns.bind_character(
               ctx.owner,
               ctx.world.id,
               next.id,
               ctx.owner.user.id,
               "mara",
               "reassigned"
             )

    assert {:ok, ^original} =
             Campaigns.bind_character(
               ctx.owner,
               ctx.world.id,
               ctx.campaign.id,
               ctx.owner.user.id,
               "mara",
               "original"
             )

    assert Repo.get!(Binding, reassigned.id).campaign_id == next.id
    assert {:ok, archived} = Campaigns.archive(ctx.owner, ctx.world.id, ctx.campaign.id, 0)
    assert {:ok, ^archived} = Campaigns.archive(ctx.owner, ctx.world.id, ctx.campaign.id, 0)
  end

  test "invitations are email-bound, role-limited, expire and cannot be replayed" do
    ctx = world_fixture()
    guest = Scope.for_user(user_fixture())
    attrs = %{"email" => guest.user.email, "role" => "gm"}

    assert {:ok, invitation} =
             Invitations.invite(ctx.owner, ctx.world.id, ctx.campaign.id, attrs, "invite")

    assert {:ok, ^invitation} =
             Invitations.invite(ctx.owner, ctx.world.id, ctx.campaign.id, attrs, "invite")

    assert {:error, :invalid_invitation} = Invitations.accept(ctx.owner, invitation.token)
    assert {:ok, _} = Invitations.accept(guest, invitation.token)
    assert {:ok, _} = Access.campaign(guest, ctx.world.id, ctx.campaign.id, ["gm"])
    assert {:error, :unauthorized} = Access.world(guest, ctx.world.id, ["steward", "builder"])
    assert {:error, :invalid_invitation} = Invitations.accept(guest, invitation.token)

    assert {:error, :invalid_invitation} =
             Invitations.invite(
               ctx.owner,
               ctx.world.id,
               ctx.campaign.id,
               %{attrs | "role" => "steward"},
               "escalate"
             )

    {:ok, expired} =
      Invitations.invite(ctx.owner, ctx.world.id, ctx.campaign.id, attrs, "expired")

    Tx.update!(Repo.get!(Invitation, expired.id), %{expires_at: ~U[2000-01-01 00:00:00.000000Z]})
    assert {:error, :invalid_invitation} = Invitations.accept(guest, expired.token)
  end

  test "multiple real gatherings neither claim a draft nor advance world time" do
    ctx = world_fixture()

    {:ok, exp} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{"name" => "Bridge", "zone_id" => "bridge"},
        "exp"
      )

    attrs = %{
      "title" => "First evening",
      "starts_at" => "2026-09-12T18:00:00Z",
      "meeting_url" => "https://example.org/meeting"
    }

    assert {:ok, gathering} = Workspace.gather(ctx.owner, ctx.world.id, exp.id, attrs, "first")
    assert {:ok, ^gathering} = Workspace.gather(ctx.owner, ctx.world.id, exp.id, attrs, "first")

    assert {:ok, _} =
             Workspace.gather(
               ctx.owner,
               ctx.world.id,
               exp.id,
               %{attrs | "title" => "Next evening", "starts_at" => "2026-09-19T18:00:00Z"},
               "second"
             )

    assert length(Workspace.gatherings(ctx.owner, ctx.world.id, exp.id)) == 2

    assert {:error, :invalid_gathering} =
             Workspace.gather(
               ctx.owner,
               ctx.world.id,
               exp.id,
               %{attrs | "meeting_url" => "javascript:alert(1)"},
               "bad"
             )

    assert {:ok, %{status: "draft", window_id: nil}} =
             Experiences.get(ctx.owner, ctx.world.id, exp.id)

    assert {:ok, %{fictional_time: 0}} = Genesis.Worlds.get_world(ctx.owner, ctx.world.id)
  end
end
