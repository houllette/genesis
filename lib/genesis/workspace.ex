defmodule Genesis.Workspace do
  @moduledoc "Campaign roster and real-world gathering metadata; none of these operations advance fiction."
  import Ecto.Query
  alias Genesis.Accounts.User
  alias Genesis.Content.Comparison
  alias Genesis.Core.Scope
  alias Genesis.Core.State
  alias Genesis.Experiences

  alias Genesis.Persistence.{
    Access,
    Binding,
    CampaignMember,
    Checkpoint,
    Codec,
    Gathering,
    Snapshot,
    Snapshots,
    Tx
  }

  alias Genesis.Repo

  @spec experience_view(scope :: term(), world :: String.t(), experience :: String.t()) :: term()
  def experience_view(scope, world, experience) do
    with {:ok, exp} <- Experiences.get(scope, world, experience),
         %Snapshot{} = snapshot <- Repo.get_by(Snapshot, world_id: world, experience_id: exp.id),
         {:ok, scene} <- Snapshots.load(snapshot) do
      role =
        if match?({:ok, _}, Access.campaign(scope, world, exp.campaign_id, ["gm"])),
          do: :gm,
          else: :spectator

      checkpoint_view(scene, exp, role)
    else
      {:error, _reason} = error -> error
      _ -> {:error, :unavailable}
    end
  end

  defp checkpoint_view(scene, exp, role) do
    viewer = %{role: role, actor_id: nil}

    with %Checkpoint{world_id: world} = checkpoint when world == exp.world_id <-
           Repo.get(Checkpoint, exp.base_checkpoint_id),
         {:ok, base} <- Codec.load_state(checkpoint.state),
         true <- Codec.digest(base) == checkpoint.digest,
         true <- checkpoint_compatible?(base, scene),
         {:ok, before} <- State.view(base, viewer),
         {:ok, working} <- State.view(scene, viewer) do
      {:ok, Map.put(working, :changes, Comparison.changes(before, working))}
    else
      _ -> {:error, :invalid_checkpoint}
    end
  end

  defp checkpoint_compatible?(base, scene),
    do:
      base.scope.world_id == scene.scope.world_id and
        base.scope.generation == scene.scope.generation and
        base.zone_id == scene.zone_id and base.rules_ref == scene.rules_ref and
        base.time.calendar_id == scene.time.calendar_id and
        base.time.calendar_version == scene.time.calendar_version

  @spec roster(scope :: term(), world :: String.t(), campaign :: String.t()) :: [map()]
  def roster(scope, world, campaign) do
    case Access.campaign(scope, world, campaign, ["gm"]) do
      {:ok, _} ->
        Repo.all(
          from m in CampaignMember,
            join: u in User,
            on: u.id == m.user_id,
            where: m.campaign_id == ^campaign and is_nil(m.revoked_at),
            order_by: u.email,
            select: %{id: u.id, email: u.email, role: m.role}
        )

      _ ->
        []
    end
  end

  @spec bindings(scope :: term(), world :: String.t(), campaign :: String.t()) :: [Binding.t()]
  def bindings(scope, world, campaign) do
    case Access.campaign(scope, world, campaign, ["gm"]) do
      {:ok, _} ->
        Repo.all(from b in Binding, where: b.campaign_id == ^campaign, order_by: b.actor_id)

      _ ->
        []
    end
  end

  @spec gather(
          scope :: term(),
          world :: String.t(),
          experience :: String.t(),
          attrs :: map(),
          request :: String.t()
        ) :: term()
  def gather(scope, world, experience, attrs, request) do
    Tx.run(world, fn record ->
      with {:ok, exp} <- Experiences.get(scope, world, experience, ["gm"]),
           {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(request),
           {:ok, fields} <- gathering_fields(attrs) do
        gather_or_restore(record, exp, user, fields, attrs, request)
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_gathering}
      end
    end)
  end

  defp gather_or_restore(world, exp, user, fields, attrs, request) do
    payload = {exp.id, attrs}

    case Tx.receipt(world.id, "gatherings", user, request, payload) do
      {:ok, %{"gathering_id" => id}} ->
        {:ok, Repo.get!(Gathering, id)}

      :new ->
        gathering =
          Tx.insert!(
            Gathering,
            Map.merge(fields, %{world_id: world.id, experience_id: exp.id, request_id: request})
          )

        Tx.event!(world, %{
          scope_key: "gatherings",
          kind: "world",
          campaign_id: exp.campaign_id,
          principal_id: user,
          audience_users: [user],
          event:
            Codec.dump!(%{type: "gathering_saved", result: %{"gathering_id" => gathering.id}})
        })

        Tx.remember!(world.id, "gatherings", user, request, payload, %{
          "gathering_id" => gathering.id
        })

        {:ok, gathering}

      error ->
        error
    end
  end

  defp gathering_fields(attrs) when is_map(attrs) do
    with true <-
           Map.keys(attrs) -- ~w(title starts_at meeting_url) == [] and Scope.id?(attrs["title"]),
         {:ok, time} <- utc(attrs["starts_at"]),
         true <- meeting_url?(Map.get(attrs, "meeting_url", "")) do
      {:ok,
       %{title: attrs["title"], starts_at: time, meeting_url: Map.get(attrs, "meeting_url", "")}}
    else
      _ -> {:error, :invalid_gathering}
    end
  end

  defp gathering_fields(_attrs), do: {:error, :invalid_gathering}

  defp utc(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, time, 0} -> {:ok, %{time | microsecond: {elem(time.microsecond, 0), 6}}}
      _ -> {:error, :invalid_date}
    end
  end

  defp utc(_iso), do: {:error, :invalid_date}
  defp meeting_url?(""), do: true

  defp meeting_url?(url) when is_binary(url) and byte_size(url) <= 2000 do
    uri = URI.parse(url)

    uri.scheme in ["https", "http"] and is_binary(uri.host) and uri.host != "" and
      is_nil(uri.userinfo)
  end

  defp meeting_url?(_url), do: false

  @spec gatherings(scope :: term(), world :: String.t(), experience :: String.t()) :: [
          Gathering.t()
        ]
  def gatherings(scope, world, experience) do
    case Experiences.get(scope, world, experience) do
      {:ok, _} ->
        Repo.all(
          from g in Gathering, where: g.experience_id == ^experience, order_by: g.starts_at
        )

      _ ->
        []
    end
  end
end
