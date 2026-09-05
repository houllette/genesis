defmodule Genesis.Phase07Fixtures do
  @moduledoc false
  alias Genesis.Campaigns
  alias Genesis.Core.Actor
  alias Genesis.Core.Curation
  alias Genesis.Core.Persona
  alias Genesis.Persistence.Bootstrap
  alias Genesis.Persistence.Snapshot
  alias Genesis.Persistence.Snapshots
  alias Genesis.Repo
  alias Genesis.WorldFixtures
  alias Genesis.WorldNetwork

  def prepared_world(opts \\ []) do
    transform = fn state ->
      npc =
        struct(Actor,
          id: "orin",
          name: "Orin",
          kind: :npc,
          persona: Persona.materialize("orin", %{}),
          skills: %{"diplomacy" => 1},
          companion_policy: %{"version" => 1, "willing" => true, "max_trips" => 2}
        )

      item =
        struct(Genesis.Core.Item,
          id: "orin-satchel",
          name: "Orin's satchel",
          owner: {:actor, npc.id}
        )

      %{
        state
        | actors: Map.put(state.actors, npc.id, npc),
          items: Map.put(state.items, item.id, item)
      }
    end

    ctx =
      WorldFixtures.world_fixture(
        Keyword.merge([zero_duration: true, ruleset: "fantasy_local", transform: transform], opts)
      )

    for zone <- ["docks", "hill"] do
      state = %{
        ctx.seed
        | zone_id: zone,
          name: String.capitalize(zone),
          actors: %{},
          items: %{},
          knowledge: %{},
          settlement: nil
      }

      courier = %{ctx.seed.actors["courier"] | id: zone <> "-courier", name: zone <> " courier"}
      state = %{state | actors: %{courier.id => courier}}

      state =
        Enum.reduce(~w(merchant representative), state, fn role, state ->
          {:ok, next} =
            Curation.apply(state, zone <> "-" <> role, %{
              "kind" => "npc",
              "name" => zone <> " " <> role
            })

          next
        end)

      attrs =
        Genesis.SettlementFixtures.configuration(opts)
        |> Map.merge(%{
          "merchant_id" => zone <> "-merchant",
          "representative_id" => zone <> "-representative"
        })

      {:ok, state} = Curation.apply(state, zone <> "-market", attrs)

      holdings =
        if Keyword.get(opts, :profile) == "mutual_aid",
          do: [{"grain", 12}],
          else: [{"grain", 12}, {"coin", 200}]

      state =
        Enum.reduce(holdings, state, fn {commodity, quantity}, state ->
          {:ok, next} =
            Curation.apply(state, zone <> "-" <> commodity, %{
              "kind" => "stock",
              "name" => commodity,
              "owner_id" => zone <> "-merchant",
              "commodity" => commodity,
              "quantity" => quantity,
              "reason" => "Opening stock"
            })

          next
        end)

      {:ok, _} = Bootstrap.seed(ctx.owner, ctx.world.id, state, zone)
    end

    edges = [{"bridge", "docks"}, {"docks", "bridge"}, {"docks", "hill"}, {"hill", "docks"}]

    Enum.with_index(edges)
    |> Enum.each(fn {{from, to}, revision} ->
      {:ok, _} =
        WorldNetwork.persist(
          ctx.owner,
          ctx.world.id,
          %{generation: 0, revision: revision},
          %{
            "type" => "connection",
            "from" => from,
            "to" => to,
            "condition" => "open",
            "capacity" => 4,
            "visibility" => "public"
          },
          "link-#{revision}"
        )
    end)

    {:ok, network} = WorldNetwork.view(ctx.owner, ctx.world.id)

    network.institutions
    |> Enum.with_index(4)
    |> Enum.each(fn {institution, revision} ->
      {:ok, _} =
        WorldNetwork.persist(
          ctx.owner,
          ctx.world.id,
          %{generation: 0, revision: revision},
          %{
            "type" => "jurisdiction",
            "institution_id" => institution.id,
            "zones" => [institution.home_zone],
            "visibility" => "public"
          },
          "register-#{revision}"
        )
    end)

    {:ok, _} =
      Campaigns.bind_character(
        ctx.owner,
        ctx.world.id,
        ctx.campaign.id,
        ctx.owner.user.id,
        "mara",
        "bind"
      )

    ctx
  end

  def active_world(opts \\ []), do: opts |> prepared_world() |> WorldFixtures.experience_fixture()

  def working(ctx, zone) do
    row = Repo.get_by!(Snapshot, experience_id: ctx.experience.id, zone_id: zone)
    {:ok, state} = Snapshots.load(row)
    state
  end
end
