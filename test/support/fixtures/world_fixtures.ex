defmodule Genesis.WorldFixtures do
  @moduledoc false
  alias Genesis.Accounts.Scope, as: UserScope
  alias Genesis.Campaigns
  alias Genesis.Core.Scope
  alias Genesis.Experiences
  alias Genesis.Persistence.{Bootstrap, Snapshot, Tx}
  alias Genesis.{Repo, SceneFixtures, Systems, Worlds}
  import Genesis.AccountsFixtures

  def world_fixture(opts \\ []) do
    owner = UserScope.for_user(user_fixture())
    {:ok, original} = Systems.load(Keyword.get(opts, :ruleset, "fantasy_demo"))

    data =
      if Keyword.get(opts, :zero_duration, false),
        do: put_in(original.data["actions"]["help"]["duration"]["value"], 0).data,
        else: original.data

    data =
      if Keyword.get(opts, :zero_duration, false) and data["local"],
        do: put_in(data["local"]["rest"]["duration"], 0),
        else: data

    {:ok, bundle} = Systems.Bundle.validate(data)

    {:ok, world} =
      Worlds.create_world(owner, %{"name" => "Ashfall", "ruleset" => "fantasy_demo"}, "world",
        bundle: data
      )

    world =
      if Keyword.has_key?(opts, :initial_time),
        do:
          Tx.update!(world, %{
            fictional_time: Keyword.fetch!(opts, :initial_time)
          }),
        else: world

    seed =
      if data["local"],
        do: Genesis.SettlementFixtures.scene(Systems.scene_rules(bundle), opts),
        else: SceneFixtures.scene(Systems.scene_rules(bundle))

    seed =
      if Keyword.get(opts, :private_target, false),
        do: put_in(seed.actors["moll"].audience, {:actors, ["mara", "moll"]}),
        else: seed

    scope = struct(Scope, world_id: world.id, generation: world.generation, kind: :published)

    time = %{
      seed.time
      | world_id: world.id,
        calendar_id: world.calendar_id,
        value: world.fictional_time
    }

    seed = %{
      seed
      | scope: scope,
        time: time,
        knowledge:
          Map.new(seed.knowledge, fn {id, record} ->
            {id,
             %{
               record
               | scope: scope,
                 occurred_at: time.value,
                 learned_at: if(record.learned_at, do: time.value)
             }}
          end)
    }

    seed = Keyword.get(opts, :transform, &Function.identity/1).(seed)
    {:ok, %{"snapshot_id" => snapshot_id}} = Bootstrap.seed(owner, world.id, seed, "seed")

    {:ok, campaign} =
      Campaigns.create_campaign(owner, world.id, %{"name" => "Dock Crew"}, "campaign")

    %{
      owner: owner,
      world: Repo.get!(Genesis.Persistence.World, world.id),
      campaign: campaign,
      published: Repo.get!(Snapshot, snapshot_id),
      seed: seed,
      bundle: bundle
    }
  end

  def experience_fixture(ctx, opts \\ []) do
    {:ok, exp} =
      Experiences.create(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        %{
          "name" => Keyword.get(opts, :name, "Bridge dispute"),
          "zone_id" => "bridge",
          "participants" => Keyword.get(opts, :participants, ["mara"]),
          "start_offset" => Keyword.get(opts, :start_offset, 0)
        },
        Keyword.get(opts, :request_id, "experience")
      )

    {:ok, exp} = Experiences.start(ctx.owner, ctx.world.id, exp.id, exp.revision)

    %{ctx | world: Repo.get!(Genesis.Persistence.World, ctx.world.id)}
    |> Map.merge(%{experience: exp, snapshot: Repo.get_by!(Snapshot, experience_id: exp.id)})
  end
end
