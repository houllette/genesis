defmodule Genesis.WorldNetwork do
  @moduledoc "World-owned connection and jurisdiction curation. Geography assessment is read-only; actor travel is not enabled."
  alias Genesis.Content.NetworkCatalog
  alias Genesis.Core.{Network, Scope}
  alias Genesis.Engine.Runtime
  alias Genesis.Persistence.{Access, Codec, Curation, Draft, Tx}
  alias Genesis.Persistence.Network, as: Record
  alias Genesis.Repo

  @spec save(
          scope :: term(),
          world :: String.t(),
          expected :: %{generation: non_neg_integer(), revision: non_neg_integer()},
          command :: map(),
          request :: String.t()
        ) :: term()
  def save(scope, world, expected, command, request),
    do: Runtime.call(scope, world, {:network_save, expected, command, request})

  @doc false
  @spec persist(
          scope :: term(),
          world :: String.t(),
          expected :: map(),
          command :: map(),
          request :: String.t()
        ) :: term()
  def persist(scope, world, expected, command, request) do
    Tx.run(world, fn world ->
      with :ok <- Access.world(scope, world.id, ["steward", "builder"]),
           {:ok, user} <- Access.user_id(scope),
           :ok <- fence(world, expected),
           true <- Scope.id?(request),
           {:ok, _} <- Codec.dump(command) do
        save_or_restore(world, user, expected, command, request)
      else
        false -> {:error, :invalid_request}
        error -> error
      end
    end)
  end

  defp save_or_restore(world, user, expected, command, request) do
    key = "network:" <> Integer.to_string(world.generation)

    case Tx.receipt(world.id, key, user, request, {expected, command}) do
      :new -> save_new(world, user, key, expected, command, request)
      result -> result
    end
  end

  defp fence(world, %{generation: generation, revision: revision} = expected)
       when map_size(expected) == 2 and is_integer(revision) and revision >= 0 do
    if generation == world.generation, do: :ok, else: {:error, :stale_generation}
  end

  defp fence(_world, _expected), do: {:error, :invalid_request}

  defp save_new(world, user, key, expected, command, request) do
    revision = expected.revision

    with {:ok, catalog} <- NetworkCatalog.load(world, %{role: :gm}),
         {:ok, row, before, ^revision} <- current(world, catalog),
         {:ok, next} <- Network.apply(before, command, catalog) do
      result = store(world, user, key, row, before, next, revision, command)
      Tx.remember!(world.id, key, user, request, {expected, command}, result)
      {:ok, result}
    else
      {:ok, _, _, _} -> {:error, :stale_revision}
      error -> error
    end
  end

  defp store(world, user, key, row, before, next, revision, command) do
    if Curation.window_open?(world.id) do
      draft =
        Tx.insert!(Draft, %{
          world_id: world.id,
          zone_id: "@network",
          kind: "network",
          entity_id: world.id,
          author_id: user,
          base_revision: world.revision,
          attrs: %{
            "version" => 1,
            "generation" => world.generation,
            "network_revision" => revision,
            "command" => command
          }
        })

      result = %{"status" => "draft", "draft_id" => draft.id, "revision" => revision}
      audit(world, user, key, "network_draft_saved", result, before, next)
      result
    else
      fields = %{
        world_id: world.id,
        generation: world.generation,
        revision: revision + 1,
        data: next
      }

      if row, do: Tx.update!(row, fields), else: Tx.insert!(Record, fields)
      world = Tx.update!(world, %{revision: world.revision + 1})
      result = %{"status" => "published", "revision" => revision + 1}
      audit(world, user, key, "network_saved", result, before, next)
      result
    end
  end

  defp audit(world, user, key, type, result, before, next),
    do:
      Tx.event!(world, %{
        scope_key: key,
        kind: "world",
        principal_id: user,
        audience_users: [user],
        event: Codec.dump!(%{"before" => before, "after" => next, type: type, result: result})
      })

  defp current(world, catalog) do
    case Repo.get_by(Record, world_id: world.id, generation: world.generation) do
      nil ->
        {:ok, nil, Network.new(world.id, world.generation), 0}

      row ->
        with {:ok, data} <- Network.restore(row.data, catalog), do: {:ok, row, data, row.revision}
    end
  end

  @spec view(scope :: term(), world :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, atom()}
  def view(scope, world, opts \\ []) do
    Tx.run(world, fn world ->
      with :ok <- Access.world(scope, world.id),
           gm =
             not Keyword.get(opts, :public, false) and
               Access.world(scope, world.id, ["steward", "builder"]) == :ok,
           {:ok, catalog} <-
             NetworkCatalog.load(world, %{role: if(gm, do: :gm, else: :spectator)}),
           {:ok, _row, data, revision} <- current(world, catalog) do
        {:ok, project(world, data, catalog, revision, gm)}
      end
    end)
  end

  defp project(world, data, catalog, revision, gm) do
    connections = Enum.filter(data["connections"], &(gm or &1["visibility"] == "public"))

    institutions =
      for {id, local} <- catalog.institutions,
          local.visible,
          gm or match?(%{"visibility" => "public"}, data["institutions"][id]) do
        row = data["institutions"][id]

        %{
          id: id,
          name: local.name,
          home_zone: local.home_zone,
          local_id: local.local_id,
          registered: not is_nil(row),
          zones: if(row, do: row["zones"], else: [local.home_zone]),
          visibility: if(row, do: row["visibility"], else: "gm")
        }
      end

    %{
      world: world,
      generation: world.generation,
      revision: revision,
      can_edit: gm,
      window_open: Curation.window_open?(world.id),
      connections: connections,
      institutions: Enum.sort_by(institutions, & &1.id),
      zones: Enum.sort_by(Map.values(catalog.zones), &{&1.name, &1.id})
    }
  end

  @doc "Inspect current visible published geography. A positive result is not a travel authorization or footprint claim."
  @spec assess(
          scope :: term(),
          world :: String.t(),
          from :: String.t(),
          to :: String.t(),
          size :: integer()
        ) :: term()
  def assess(scope, world, from, to, size) do
    with {:ok, view} <- view(scope, world) do
      Network.assess(%{"connections" => view.connections}, from, to, size)
    end
  end
end
