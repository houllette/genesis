defmodule Genesis.Worlds do
  @moduledoc "World library and stewardship. Canonical scene edits go through engine authority."
  import Ecto.Query
  alias Genesis.Accounts.User
  alias Genesis.Core.Scope
  alias Genesis.Persistence.{Access, Codec, Tx, World, WorldMember}
  alias Genesis.{Repo, Systems}
  alias Genesis.Systems.Bundle
  alias Genesis.Time.Calendar

  @spec create_world(scope :: term(), attrs :: map(), request_id :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_world(scope, attrs, request_id, opts \\ []) do
    with {:ok, user} <- Access.user_id(scope),
         true <- valid_world?(attrs) and Scope.id?(request_id),
         {:ok, bundle} <- selected_bundle(attrs, opts) do
      Repo.transact(fn ->
        Repo.one!(from u in User, where: u.id == ^user, lock: "FOR UPDATE")
        world_id = named_id(["world", user, request_id])
        payload = {attrs, bundle.ref}

        create_or_restore(
          Repo.get(World, world_id),
          user,
          world_id,
          attrs,
          bundle,
          request_id,
          payload
        )
      end)
    else
      {:error, :unauthorized} = error -> error
      _ -> {:error, :invalid_world}
    end
  end

  defp create_or_restore(nil, user, world_id, attrs, bundle, request, payload),
    do: create(user, world_id, attrs, bundle, request, payload)

  defp create_or_restore(world, user, _id, _attrs, _bundle, request, payload) do
    case Tx.receipt(world.id, "setup", user, request, payload) do
      {:ok, _result} -> {:ok, world}
      _ -> {:error, :request_conflict}
    end
  end

  @spec list_worlds(scope :: term()) :: [map()]
  def list_worlds(scope) do
    case Access.user_id(scope) do
      {:ok, user} ->
        Repo.all(
          from w in World,
            join: m in WorldMember,
            on: m.world_id == w.id,
            where: m.user_id == ^user and is_nil(m.revoked_at),
            order_by: [asc: w.name, asc: w.id]
        )

      _ ->
        []
    end
  end

  @spec get_world(scope :: term(), world_id :: String.t()) :: {:ok, World.t()} | {:error, atom()}
  def get_world(scope, world_id) do
    with :ok <- Access.world(scope, world_id), do: {:ok, Repo.get!(World, world_id)}
  end

  @spec set_role(
          scope :: term(),
          world_id :: String.t(),
          user_id :: String.t(),
          role :: String.t()
        ) :: {:ok, map()} | {:error, term()}
  @spec set_role(
          scope :: term(),
          world :: String.t(),
          user :: String.t(),
          role :: String.t(),
          request :: String.t() | nil
        ) :: term()
  def set_role(scope, world_id, user_id, role, request \\ nil) do
    change = fn -> change_role(scope, world_id, user_id, role) end

    Tx.run(world_id, fn _world ->
      with :ok <- Access.world(scope, world_id, ["steward"]),
           {:ok, user} <- Access.user_id(scope) do
        Tx.record_command(
          world_id,
          user,
          "world-roles",
          request,
          {user_id, role},
          WorldMember,
          change
        )
      end
    end)
  end

  defp change_role(scope, world_id, user_id, role) do
    Tx.run(world_id, fn world ->
      with :ok <- Access.world(scope, world_id, ["steward"]),
           true <- role in ["steward", "builder", "viewer"],
           true <- Access.uuid?(user_id),
           %User{} <- Repo.get(User, user_id),
           true <- user_id != world.creator_id or role == "steward" do
        member = Repo.get_by(WorldMember, world_id: world_id, user_id: user_id)
        Tx.metadata!(world, scope, "world_role_changed", %{"user_id" => user_id, "role" => role})

        {:ok,
         upsert_member(member, %{
           world_id: world_id,
           user_id: user_id,
           role: role,
           revoked_at: nil
         })}
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_role}
      end
    end)
  end

  defp upsert_member(nil, attrs), do: Tx.insert!(WorldMember, attrs)
  defp upsert_member(member, attrs), do: Tx.update!(member, attrs)

  @spec named_id(parts :: list()) :: String.t()
  def named_id(parts) do
    <<a::48, _::4, b::12, _::2, c::62, _rest::binary>> =
      :crypto.hash(:sha256, Jason.encode!(parts))

    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end

  defp selected_bundle(attrs, opts) do
    case Keyword.get(opts, :bundle) do
      nil -> Systems.load(attrs["ruleset"])
      data -> Bundle.validate(data)
    end
  end

  defp valid_world?(attrs) when is_map(attrs),
    do:
      Enum.all?(Map.keys(attrs), &(&1 in ~w(name ruleset profile calendar))) and
        Scope.id?(attrs["name"]) and
        valid_calendar?(Map.get(attrs, "calendar", %{})) and
        Map.get(attrs, "profile", "village") in ["village", "frontier"]

  defp valid_world?(_attrs), do: false

  defp valid_calendar?(calendar) when calendar == %{}, do: true
  defp valid_calendar?(calendar), do: Calendar.validate(calendar) == :ok

  defp create(user, id, attrs, bundle, request_id, payload) do
    world =
      Tx.insert!(World, %{
        id: id,
        creator_id: user,
        name: attrs["name"],
        bundle: bundle.data,
        profile: Map.get(attrs, "profile", "village"),
        calendar: Map.get(attrs, "calendar", %{}),
        calendar_id: get_in(attrs, ["calendar", "id"]) || "ordinal",
        calendar_version: get_in(attrs, ["calendar", "version"]) || 1
      })

    Tx.insert!(WorldMember, %{world_id: id, user_id: user, role: "steward"})

    Tx.event!(world, %{
      scope_key: "setup",
      kind: "world",
      principal_id: user,
      event: Codec.dump!(%{type: "world_created", result: %{"name" => world.name}}),
      audience_users: [user]
    })

    Tx.remember!(id, "setup", user, request_id, payload, %{"world_id" => id})
    {:ok, Repo.get!(World, id)}
  end
end
