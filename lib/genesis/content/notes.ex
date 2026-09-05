defmodule Genesis.Content.Notes do
  @moduledoc "Linked authored notes are labelled assertions, never engine facts. Private means author-only."
  import Ecto.Query
  alias Genesis.Core.Scope
  alias Genesis.Core.State
  alias Genesis.Persistence.{Access, Codec, Entity, Note, Snapshots, Tx, World}
  alias Genesis.Repo

  @spec save(
          scope :: term(),
          world :: String.t(),
          id :: String.t() | nil,
          revision :: integer(),
          attrs :: map(),
          request :: String.t()
        ) :: term()
  def save(scope, world, id, revision, attrs, request) do
    Tx.run(world, fn record ->
      with :ok <- Access.world(scope, world, ["steward", "builder"]),
           {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(request) and valid_attrs?(attrs),
           true <-
             Repo.exists?(
               from e in Entity,
                 where: e.world_id == ^world and e.entity_id == ^attrs["entity_id"]
             ) do
        save_or_restore(record, user, id, revision, attrs, request)
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_note}
      end
    end)
  end

  defp save_or_restore(world, user, id, revision, attrs, request) do
    payload = {id, revision, attrs}

    case Tx.receipt(world.id, "notes", user, request, payload) do
      {:ok, %{"note_id" => id}} -> {:ok, Repo.get!(Note, id)}
      :new -> save_new(world, user, id, revision, attrs, request)
      error -> error
    end
  end

  defp save_new(world, user, id, revision, attrs, request) do
    with {:ok, original} <- existing(world.id, user, id, revision) do
      fields = %{
        world_id: world.id,
        author_id: user,
        entity_id: attrs["entity_id"],
        title: attrs["title"],
        body: attrs["body"],
        kind: attrs["kind"],
        visibility: attrs["visibility"],
        revision: revision + 1
      }

      note = upsert(original, fields)

      Tx.event!(world, %{
        scope_key: "notes",
        kind: "world",
        principal_id: user,
        audience_users: [user],
        event: Codec.dump!(%{type: "note_saved", result: %{"note_id" => note.id}})
      })

      Tx.remember!(world.id, "notes", user, request, {id, revision, attrs}, %{
        "note_id" => note.id
      })

      {:ok, note}
    end
  end

  defp existing(_world, _user, nil, 0), do: {:ok, nil}

  defp existing(world, user, id, revision) do
    with true <- Access.uuid?(id),
         %Note{revision: ^revision} = note <-
           Repo.get_by(Note, id: id, world_id: world, author_id: user) do
      {:ok, note}
    else
      _ -> {:error, :stale_revision}
    end
  end

  defp upsert(nil, attrs), do: Tx.insert!(Note, attrs)
  defp upsert(note, attrs), do: Tx.update!(note, attrs)

  defp valid_attrs?(attrs) when is_map(attrs),
    do:
      Map.keys(attrs) -- ~w(entity_id title body kind visibility) == [] and
        Scope.id?(attrs["entity_id"]) and Scope.id?(attrs["title"]) and
        is_binary(attrs["body"]) and byte_size(attrs["body"]) in 1..10_000 and
        String.valid?(attrs["body"]) and
        attrs["kind"] in ~w(note plan belief) and attrs["visibility"] in ~w(private public)

  defp valid_attrs?(_attrs), do: false

  @spec list(scope :: term(), world :: String.t(), opts :: keyword()) :: [Note.t()]
  def list(scope, world, opts \\ []) do
    with :ok <- Access.world(scope, world), {:ok, user} <- Access.user_id(scope) do
      public = Keyword.get(opts, :public, false)

      query =
        from n in Note,
          where:
            n.world_id == ^world and
              (n.visibility == "public" or (n.author_id == ^user and not (^public))),
          order_by: n.inserted_at

      query
      |> linked_place(Keyword.get(opts, :zone_id))
      |> Repo.all()
      |> visible_links(scope, world, public)
    else
      _ -> []
    end
  end

  defp linked_place(query, nil), do: query

  defp linked_place(query, zone),
    do:
      from(n in query,
        join: e in Entity,
        on: e.world_id == n.world_id and e.entity_id == n.entity_id,
        where: e.zone_id == ^zone,
        distinct: true
      )

  defp visible_links(notes, scope, world, public) do
    role =
      if not public and Access.world(scope, world, ["steward", "builder"]) == :ok,
        do: :gm,
        else: :spectator

    visible =
      Repo.get!(World, world)
      |> Snapshots.published()
      |> Enum.flat_map(&visible_ids(&1, role))
      |> MapSet.new()

    Enum.filter(notes, &MapSet.member?(visible, &1.entity_id))
  end

  defp visible_ids(snapshot, role) do
    with {:ok, scene} <- Snapshots.load(snapshot),
         {:ok, view} <- State.view(scene, %{role: role, actor_id: nil}) do
      [view.zone_id | Enum.map(view.actors ++ view.items, & &1.id)]
    else
      _ -> []
    end
  end
end
