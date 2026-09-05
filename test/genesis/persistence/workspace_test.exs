defmodule Genesis.Persistence.WorkspaceTest do
  use Genesis.DataCase, async: true
  alias Genesis.Accounts.Scope
  alias Genesis.{Campaigns, Worlds}
  import Genesis.AccountsFixtures

  test "world creation is scoped, validated and idempotent; campaign GM does not become steward" do
    owner = Scope.for_user(user_fixture())
    other = Scope.for_user(user_fixture())
    attrs = %{"name" => "Ashfall", "ruleset" => "fantasy_demo", "profile" => "village"}
    assert {:ok, world} = Worlds.create_world(owner, attrs, "create-world")
    assert {:ok, same} = Worlds.create_world(owner, attrs, "create-world")
    assert same.id == world.id

    assert {:error, :request_conflict} =
             Worlds.create_world(owner, Map.put(attrs, "name", "Changed"), "create-world")

    assert Worlds.list_worlds(other) == []

    assert {:error, :unauthorized} =
             Campaigns.create_campaign(other, world.id, %{"name" => "Intruder"}, "bad")

    assert {:ok, campaign} =
             Campaigns.create_campaign(owner, world.id, %{"name" => "Dock Crew"}, "campaign")

    assert {:ok, _} = Campaigns.add_member(owner, world.id, campaign.id, other.user.id, "gm")
    assert {:ok, _} = Campaigns.get_campaign(other, world.id, campaign.id)
    assert {:error, :unauthorized} = Worlds.set_role(other, world.id, other.user.id, "steward")
    assert {:error, :unauthorized} = Worlds.set_role(other, world.id, owner.user.id, "viewer")

    assert {:error, :invalid_world} =
             Worlds.create_world(owner, Map.put(attrs, "ruleset", "../secret"), "invalid")
  end

  test "database membership and campaign world constraints reject cross-world bindings" do
    owner = Scope.for_user(user_fixture())

    {:ok, one} =
      Worlds.create_world(owner, %{"name" => "One", "ruleset" => "fantasy_demo"}, "one")

    {:ok, two} =
      Worlds.create_world(owner, %{"name" => "Two", "ruleset" => "cyberpunk_demo"}, "two")

    {:ok, campaign} = Campaigns.create_campaign(owner, one.id, %{"name" => "Crew"}, "crew")
    assert {:error, :unavailable} = Campaigns.get_campaign(owner, two.id, campaign.id)

    assert {:error, :unavailable} =
             Campaigns.add_member(owner, two.id, campaign.id, owner.user.id, "gm")

    newcomer = user_fixture()
    assert {:ok, _member} = Worlds.set_role(owner, two.id, newcomer.id, "viewer")

    changes =
      Ecto.Changeset.change(%Genesis.Persistence.CampaignMember{},
        world_id: two.id,
        campaign_id: campaign.id,
        user_id: newcomer.id,
        role: "player"
      )
      |> Ecto.Changeset.foreign_key_constraint(:world_id, name: :campaign_world)

    assert {:error, invalid} = Repo.insert(changes)
    assert {"does not exist", _} = invalid.errors[:world_id]
  end
end
