defmodule Genesis.Experiences do
  @moduledoc "Durable adventure setup. Starting claims a bounded published footprint; wall time never advances fiction."
  import Ecto.Query
  alias Genesis.Core.{Scope, State}

  alias Genesis.Persistence.{
    Access,
    Binding,
    Claim,
    Codec,
    Entity,
    Experience,
    Snapshots,
    Tx,
    Window
  }

  alias Genesis.Repo

  @spec create(
          scope :: term(),
          world_id :: String.t(),
          campaign_id :: String.t(),
          attrs :: map(),
          request_id :: String.t()
        ) :: {:ok, Experience.t()} | {:error, term()}
  def create(scope, world_id, campaign_id, attrs, request) do
    Tx.run(world_id, fn world ->
      with {:ok, %{archived: false}} <- Access.campaign(scope, world_id, campaign_id, ["gm"]),
           {:ok, user} <- Access.user_id(scope),
           true <- valid_attrs?(attrs) and Scope.id?(request),
           true <-
             Repo.exists?(
               from e in Entity,
                 where:
                   e.world_id == ^world_id and e.kind == "zone" and
                     e.entity_id == ^attrs["zone_id"]
             ) do
        payload = {campaign_id, attrs}

        create_or_restore(world, campaign_id, user, attrs, request, payload)
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_experience}
      end
    end)
  end

  defp create_or_restore(world, campaign_id, user, attrs, request, payload) do
    world_id = world.id

    case Tx.receipt(world_id, "experiences", user, request, payload) do
      {:ok, %{"experience_id" => id}} ->
        {:ok, Repo.get!(Experience, id)}

      :new ->
        experience =
          Tx.insert!(Experience, %{
            world_id: world_id,
            campaign_id: campaign_id,
            name: attrs["name"],
            zone_id: attrs["zone_id"],
            participants: Map.get(attrs, "participants", [])
          })

        Tx.remember!(world_id, "experiences", user, request, payload, %{
          "experience_id" => experience.id
        })

        Tx.event!(world, %{
          scope_key: "experiences",
          kind: "world",
          campaign_id: campaign_id,
          principal_id: user,
          audience_users: [user],
          event:
            Codec.dump!(%{
              type: "experience_prepared",
              result: %{"experience_id" => experience.id}
            })
        })

        {:ok, experience}

      error ->
        error
    end
  end

  @spec start(
          scope :: term(),
          world_id :: String.t(),
          experience_id :: String.t(),
          revision :: non_neg_integer()
        ) :: {:ok, Experience.t()} | {:error, term()}
  @spec start(
          scope :: term(),
          world :: String.t(),
          id :: String.t(),
          revision :: integer(),
          request :: String.t() | nil
        ) :: term()
  def start(scope, world_id, id, revision, request \\ nil) do
    change = fn -> start_new(scope, world_id, id, revision) end

    Tx.run(world_id, fn _world ->
      with {:ok, _experience} <- get(scope, world_id, id, ["gm"]),
           {:ok, user} <- Access.user_id(scope) do
        Tx.record_command(
          world_id,
          user,
          "experience-start",
          request || "start-#{id}-#{revision}",
          {id, revision},
          Experience,
          change
        )
      end
    end)
  end

  defp start_new(scope, world_id, id, revision) do
    Tx.run(world_id, fn world ->
      with {:ok, experience} <- get(scope, world_id, id, ["gm"]),
           {:ok, operator} <- Access.user_id(scope),
           true <- experience.revision == revision and experience.status == "draft",
           published_scope =
             struct(Scope, world_id: world.id, generation: world.generation, kind: :published),
           snapshot when not is_nil(snapshot) <-
             Snapshots.find(world_id, published_scope, experience.zone_id),
           {:ok, base} <- Snapshots.load(snapshot),
           :ok <- participants(experience, base),
           :ok <- available(world, base) do
        window =
          Repo.get_by(Window, world_id: world_id, status: "open") ||
            Tx.insert!(Window, %{
              world_id: world_id,
              generation: world.generation,
              base_revision: world.revision
            })

        checkpoint = Snapshots.checkpoint!(snapshot, world.cursor)

        working_scope =
          struct(Scope,
            world_id: world_id,
            generation: world.generation,
            kind: :experience,
            window_id: window.id,
            id: id
          )

        working = rescope(base, working_scope)
        working = %{working | revision: 0, elapsed: 0, events: [], status: :active}
        snapshot = Snapshots.create!(world, working, id)
        claim!(world, base, id)

        experience =
          Tx.update!(experience, %{
            window_id: window.id,
            base_checkpoint_id: checkpoint.id,
            status: "active",
            revision: revision + 1
          })

        event =
          Tx.event!(world, %{
            snapshot_id: snapshot.id,
            scope_key: snapshot.scope_key,
            kind: "experience",
            experience_id: id,
            campaign_id: experience.campaign_id,
            principal_id: operator,
            audience_users: [operator],
            event:
              Codec.dump!(%{type: "experience_started", result: %{"name" => experience.name}})
          })

        Snapshots.checkpoint!(snapshot, event.cursor)
        {:ok, experience}
      else
        {:error, _reason} = error -> error
        false -> {:error, :stale_experience}
        _ -> {:error, :unavailable}
      end
    end)
  end

  @spec get(
          scope :: term(),
          world_id :: String.t(),
          experience_id :: String.t(),
          roles :: [String.t()]
        ) :: {:ok, Experience.t()} | {:error, atom()}
  def get(scope, world, id, roles \\ ["gm", "player", "spectator"]) do
    with true <- Access.uuid?(id) and Access.uuid?(world),
         %Experience{} = exp <- Repo.get_by(Experience, id: id, world_id: world),
         {:ok, _campaign} <- Access.campaign(scope, world, exp.campaign_id, roles) do
      {:ok, exp}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :unavailable}
    end
  end

  @spec list(scope :: term(), world_id :: String.t()) :: [Experience.t()]
  def list(scope, world) do
    if Access.world(scope, world) == :ok do
      Repo.all(from e in Experience, where: e.world_id == ^world, order_by: e.inserted_at)
      |> Enum.filter(&match?({:ok, _exp}, get(scope, world, &1.id)))
    else
      []
    end
  end

  @doc false
  @spec rescope(state :: State.t(), scope :: Scope.t()) :: State.t()
  def rescope(state, scope),
    do: %{
      state
      | scope: scope,
        knowledge: Map.new(state.knowledge, fn {id, fact} -> {id, %{fact | scope: scope}} end),
        events: Enum.map(state.events, &Map.put(&1, :scope, scope))
    }

  defp valid_attrs?(attrs) when is_map(attrs),
    do:
      Enum.all?(Map.keys(attrs), &(&1 in ~w(name zone_id participants start_offset))) and
        Scope.id?(attrs["name"]) and Scope.id?(attrs["zone_id"]) and
        Map.get(attrs, "start_offset", 0) == 0 and is_list(Map.get(attrs, "participants", [])) and
        valid_participants?(Map.get(attrs, "participants", []))

  defp valid_attrs?(_attrs), do: false

  defp valid_participants?(participants),
    do:
      length(participants) <= 16 and Enum.all?(participants, &Scope.id?/1) and
        Enum.uniq(participants) == participants

  defp participants(exp, base) do
    valid =
      Enum.uniq(exp.participants) == exp.participants and
        Enum.all?(exp.participants, &match?(%{kind: :pc}, base.actors[&1]))

    conflict =
      Repo.exists?(
        from b in Binding,
          where:
            b.world_id == ^exp.world_id and
              b.actor_id in ^exp.participants and b.campaign_id != ^exp.campaign_id
      )

    if valid and not conflict, do: :ok, else: {:error, :invalid_participants}
  end

  defp resources(base),
    do:
      [{"zone", base.zone_id}] ++
        Enum.map(Map.keys(base.actors), &{"actor", &1}) ++
        Enum.map(Map.keys(base.items), &{"item", &1})

  defp available(world, base) do
    claimed =
      Enum.find(resources(base), fn {kind, id} ->
        Repo.exists?(
          from c in Claim,
            where:
              c.world_id == ^world.id and c.generation == ^world.generation and
                c.resource_kind == ^kind and c.resource_id == ^id
        )
      end)

    if claimed, do: {:error, :claimed}, else: :ok
  end

  defp claim!(world, base, exp),
    do:
      Enum.each(resources(base), fn {kind, id} ->
        Tx.insert!(Claim, %{
          world_id: world.id,
          generation: world.generation,
          resource_kind: kind,
          resource_id: id,
          experience_id: exp
        })
      end)
end
