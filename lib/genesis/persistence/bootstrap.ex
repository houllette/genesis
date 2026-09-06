defmodule Genesis.Persistence.Bootstrap do
  @moduledoc "Initial scene admission only; existing snapshots are never replaced by seed data."
  import Ecto.Query
  alias Genesis.Core.{Scope, State}
  alias Genesis.Persistence.{Access, Codec, Snapshots, Tx, Window}
  alias Genesis.Repo

  @spec seed(
          scope :: term(),
          world_id :: String.t(),
          state :: State.t(),
          request_id :: String.t()
        ) :: {:ok, map()} | {:error, term()}
  def seed(scope, world_id, state, request) do
    Tx.run(world_id, fn world ->
      with :ok <- Access.world(scope, world_id, ["steward", "builder"]),
           {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(request),
           true <- state.scope.kind == :published,
           {:ok, _state} <- State.restore(state),
           :ok <- Snapshots.compatible(world, state) do
        do_seed(world, user, state, request)
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_scene}
      end
    end)
  end

  defp do_seed(world, user, state, request) do
    payload = %{type: "seed", value: state}
    key = Snapshots.key(state.scope)

    case Tx.receipt(world.id, key, user, request, payload) do
      {:ok, result} ->
        {:ok, result}

      :new ->
        cond do
          Repo.exists?(from w in Window, where: w.world_id == ^world.id and w.status != "closed") ->
            {:error, :window_open}

          Snapshots.find(world.id, state.scope, state.zone_id) ->
            {:error, :already_exists}

          true ->
            snapshot = Snapshots.create!(world, state)
            world = Tx.update!(world, %{revision: world.revision + 1})

            event =
              Tx.event!(world, %{
                snapshot_id: snapshot.id,
                scope_key: key,
                kind: "world",
                principal_id: user,
                audience_users: [user],
                event: Codec.dump!(%{type: "zone_created", result: %{"zone_id" => state.zone_id}})
              })

            Snapshots.checkpoint!(snapshot, event.cursor)
            result = %{"snapshot_id" => snapshot.id}
            Tx.remember!(world.id, key, user, request, payload, result)
            {:ok, result}
        end

      error ->
        error
    end
  end
end
