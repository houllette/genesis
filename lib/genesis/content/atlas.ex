defmodule Genesis.Content.Atlas do
  @moduledoc "Permission-filtered linked world atlas. Descriptive records never execute mechanics."
  import Ecto.Query
  alias Genesis.Content.{AtlasCatalog, AtlasEntry}
  alias Genesis.Core.{AtlasRecord, Scope}
  alias Genesis.Engine.Runtime
  alias Genesis.Persistence.{Access, Authority, Codec, Curation, Draft, Tx}
  alias Genesis.{Repo, Worlds}

  @spec save(
          scope :: term(),
          world :: String.t(),
          id :: String.t() | nil,
          revision :: integer(),
          attrs :: map(),
          request :: String.t()
        ) :: term()
  def save(scope, world, id, revision, attrs, request),
    do: Runtime.call(scope, world, {:atlas_save, id, revision, attrs, request})

  @doc false
  @spec persist(
          scope :: term(),
          world :: String.t(),
          id :: String.t() | nil,
          revision :: integer(),
          attrs :: map(),
          request :: String.t()
        ) :: term()
  def persist(scope, world, id, revision, attrs, request) do
    Tx.run(world, fn world ->
      with :ok <- Access.world(scope, world.id, ["steward", "builder"]),
           {:ok, user} <- Access.user_id(scope),
           :ok <- command_access(scope, world, id, attrs),
           true <- Scope.id?(request) do
        save_or_restore(scope, world, user, {id, revision, attrs}, request)
      else
        false -> {:error, :invalid_request}
        error -> error
      end
    end)
  end

  defp save_or_restore(scope, world, user, payload, request) do
    key = "atlas:" <> Integer.to_string(world.generation)

    case Tx.receipt(world.id, key, user, request, payload) do
      :new -> save_new(scope, world, user, payload, request, key)
      result -> result
    end
  end

  defp save_new(scope, world, user, {id, revision, attrs} = payload, request, key) do
    entry_id = id || Worlds.named_id([world.id, world.generation, user, "atlas", request])

    with {:ok, original} <- existing(world, id, revision),
         {:ok, rows} <- rows(world),
         true <- not is_nil(original) or length(rows) < 500,
         {:ok, runtime} <-
           AtlasCatalog.published(world, %{role: :gm, actor_id: nil}),
         catalog = Map.new(Enum.map(rows, &AtlasCatalog.entry/1) ++ runtime, &{&1.id, &1}),
         {:ok, data} <- AtlasRecord.validate("record:" <> entry_id, attrs, catalog),
         :ok <- reference_access(scope, world, rows, data, runtime),
         :ok <- same_kind(original, data),
         :ok <- party_access(scope, world.id, data["campaign_id"]),
         :ok <- original_access(scope, world.id, original) do
      result = store(world, user, entry_id, original, data)
      Tx.remember!(world.id, key, user, request, payload, result)
      {:ok, result}
    else
      false -> {:error, :capacity_limit}
      error -> error
    end
  end

  defp existing(_world, nil, 0), do: {:ok, nil}

  defp existing(world, id, revision) do
    if Access.uuid?(id) do
      case Repo.get_by(AtlasEntry, world_id: world.id, generation: world.generation, id: id) do
        %{revision: ^revision} = entry -> {:ok, entry}
        _ -> {:error, :stale_revision}
      end
    else
      {:error, :stale_revision}
    end
  end

  defp same_kind(nil, _data), do: :ok
  defp same_kind(%{kind: kind}, %{"kind" => kind}), do: :ok
  defp same_kind(_entry, _data), do: {:error, :wrong_kind}
  defp original_access(_scope, _world, nil), do: :ok
  defp original_access(scope, world, entry), do: party_access(scope, world, entry.campaign_id)
  defp party_access(_scope, _world, nil), do: :ok

  defp party_access(scope, world, campaign) do
    case Access.campaign(scope, world, campaign, ["gm"]) do
      {:ok, _} -> :ok
      _ -> {:error, :unauthorized}
    end
  end

  defp command_access(scope, world, id, attrs) when is_map(attrs) do
    with :ok <- party_access(scope, world.id, attrs["campaign_id"]) do
      existing_access(scope, world, id)
    end
  end

  defp command_access(_scope, _world, _id, _attrs), do: {:error, :invalid_record}

  defp existing_access(_scope, _world, nil), do: :ok

  defp existing_access(scope, world, id) do
    with true <- Access.uuid?(id),
         %{} = entry <-
           Repo.get_by(AtlasEntry, world_id: world.id, generation: world.generation, id: id) do
      original_access(scope, world.id, entry)
    else
      _ -> {:error, :unavailable}
    end
  end

  defp reference_access(scope, world, rows, data, runtime) do
    visible = visible_rows(rows, scope, world.id, true, []) |> Enum.map(&AtlasCatalog.entry/1)
    ids = MapSet.new(visible ++ runtime, & &1.id)
    refs = Enum.reject(Enum.map(~w(parent source target), &data[&1]), &is_nil/1)
    if Enum.all?(refs, &MapSet.member?(ids, &1)), do: :ok, else: {:error, :invalid_reference}
  end

  defp store(world, user, id, original, data) do
    if Curation.window_open?(world.id) do
      draft =
        Tx.insert!(Draft, %{
          world_id: world.id,
          zone_id: "@atlas",
          entity_id: id,
          kind: "atlas",
          attrs: Map.put(data, "record_revision", if(original, do: original.revision, else: 0)),
          base_revision: world.revision,
          author_id: user
        })

      result = %{"status" => "draft", "entity_id" => id, "draft_id" => draft.id}
      audit(world, user, "atlas_draft_saved", result, nil, data)
      result
    else
      fields = %{
        id: id,
        world_id: world.id,
        generation: world.generation,
        kind: data["kind"],
        visibility: data["visibility"],
        campaign_id: data["campaign_id"],
        archived: data["archived"],
        revision: if(original, do: original.revision + 1, else: 1),
        data: Map.put(data, "version", 1)
      }

      if original,
        do: Tx.update!(original, Map.delete(fields, :id)),
        else: Tx.insert!(AtlasEntry, fields)

      world = Tx.update!(world, %{revision: world.revision + 1})
      result = %{"status" => "published", "entity_id" => id, "revision" => fields.revision}
      audit(world, user, "atlas_record_saved", result, if(original, do: original.data), data)
      result
    end
  end

  defp audit(world, user, type, result, before, next),
    do:
      Tx.event!(world, %{
        scope_key: "atlas:" <> Integer.to_string(world.generation),
        kind: "world",
        principal_id: user,
        audience_users: [user],
        event:
          Codec.dump!(%{
            "before" => before,
            "after" => Map.put(next, "version", 1),
            type: type,
            result: result
          })
      })

  @spec search(scope :: term(), world :: String.t(), query :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, atom()}
  def search(scope, world, query \\ "", opts \\ []) do
    with :ok <- query_valid(query),
         {:ok, records} <- catalog(scope, world, opts),
         do: {:ok, AtlasCatalog.page(records, query)}
  end

  @spec get(scope :: term(), world :: String.t(), reference :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, atom()}
  def get(scope, world, reference, opts \\ []) do
    with {:ok, records} <- catalog(scope, world, opts),
         %{} = record <- Enum.find(records, &(&1.id == reference)) do
      links = Enum.filter(records, &(reference in [&1.parent, &1.source, &1.target]))
      {:ok, %{record: record, links: Enum.sort_by(links, & &1.id)}}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp catalog(scope, world, opts) do
    Tx.run(world, fn world ->
      with :ok <- Access.world(scope, world.id),
           {:ok, rows} <- rows(world),
           gm =
             not Keyword.get(opts, :public, false) and
               Access.world(scope, world.id, ["steward", "builder"]) == :ok,
           {:ok, runtime} <-
             AtlasCatalog.published(world, %{
               role: if(gm, do: :gm, else: :spectator),
               actor_id: nil
             }) do
        visible = visible_rows(rows, scope, world.id, gm, opts)
        {:ok, AtlasCatalog.linked(Enum.map(visible, &AtlasCatalog.entry/1) ++ runtime)}
      end
    end)
  end

  @doc "A read-only player projection of one authorized Experience; never inherits a GM caller's omniscient view."
  @spec player_search(
          scope :: term(),
          world :: String.t(),
          experience :: String.t(),
          actor :: String.t(),
          query :: String.t()
        ) :: {:ok, map()} | {:error, atom()}
  def player_search(scope, world, experience, actor, query \\ "") do
    Tx.run(world, fn world ->
      with :ok <- query_valid(query),
           {:ok, principal, snapshot} <- Authority.principal(scope, world.id, experience, actor),
           true <- Scope.id?(actor),
           {:ok, rows} <- rows(world),
           {:ok, runtime} <- AtlasCatalog.runtime([snapshot], %{role: :player, actor_id: actor}) do
        visible =
          Enum.filter(
            rows,
            &(not &1.archived and
                (&1.visibility == "public" or
                   (&1.visibility == "party" and &1.campaign_id == principal.campaign_id)))
          )

        page =
          Enum.map(visible, &AtlasCatalog.entry/1)
          |> Kernel.++(runtime)
          |> AtlasCatalog.linked()
          |> AtlasCatalog.page(query)

        {:ok, Map.put(page, :scope, principal.scope)}
      else
        _ -> {:error, :unavailable}
      end
    end)
  end

  defp visible_rows(rows, scope, world, gm, opts) do
    Enum.filter(rows, fn row ->
      (not row.archived or (gm and Keyword.get(opts, :archived, false))) and
        (row.visibility == "public" or (gm and row.visibility == "gm") or
           party_visible?(row, scope, world, opts))
    end)
  end

  defp party_visible?(%{visibility: "party", campaign_id: campaign}, scope, world, opts),
    do:
      not Keyword.get(opts, :public, false) and
        match?({:ok, _}, Access.campaign(scope, world, campaign))

  defp party_visible?(_row, _scope, _world, _opts), do: false

  defp rows(world) do
    rows =
      Repo.all(
        from e in AtlasEntry,
          where: e.world_id == ^world.id and e.generation == ^world.generation,
          limit: 501
      )

    cond do
      length(rows) > 500 -> {:error, :capacity_limit}
      Enum.all?(rows, &valid_stored?/1) -> {:ok, rows}
      true -> {:error, :unsupported_atlas_format}
    end
  end

  defp valid_stored?(row) do
    match?({:ok, _}, AtlasRecord.restore(row.data)) and
      row.data["kind"] == row.kind and row.data["visibility"] == row.visibility and
      row.data["campaign_id"] == row.campaign_id and row.data["archived"] == row.archived
  end

  defp query_valid(query) when is_binary(query) and byte_size(query) <= 100,
    do: if(String.valid?(query), do: :ok, else: {:error, :invalid_query})

  defp query_valid(_query), do: {:error, :invalid_query}
end
