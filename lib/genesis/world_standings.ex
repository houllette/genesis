defmodule Genesis.WorldStandings do
  @moduledoc "Source-checked reports routed to the World owner. Working reports publish with their whole Experience."
  import Ecto.Query
  alias Genesis.Content.NetworkCatalog
  alias Genesis.Core.Scope
  alias Genesis.Core.Standing
  alias Genesis.Engine.Runtime
  alias Genesis.Experiences
  alias Genesis.Persistence.Access
  alias Genesis.Persistence.Codec
  alias Genesis.Persistence.Event
  alias Genesis.Persistence.GlobalDependency
  alias Genesis.Persistence.Snapshot
  alias Genesis.Persistence.Snapshots
  alias Genesis.Persistence.Standing, as: Record
  alias Genesis.Persistence.Transfers
  alias Genesis.Persistence.Tx
  alias Genesis.Repo
  alias Genesis.WorldNetwork
  alias Genesis.Worlds

  @spec report(
          scope :: term(),
          world :: String.t(),
          experience :: String.t(),
          event :: String.t(),
          request :: String.t()
        ) :: term()
  def report(scope, world, exp, event, request),
    do: Runtime.call(scope, world, {:standing_report, exp, event, request})

  @doc false
  @spec persist(
          scope :: term(),
          world :: String.t(),
          experience :: String.t(),
          event :: String.t(),
          request :: String.t()
        ) :: term()
  def persist(scope, world, exp, event, request) do
    Tx.run(world, &persist_report(scope, &1, exp, event, request))
  end

  defp persist_report(scope, world, exp, event, request) do
    with {:ok, exp} <- Experiences.get(scope, world.id, exp, ["gm"]),
         {:ok, user} <- Access.user_id(scope),
         true <- Scope.id?(request) and Access.uuid?(event),
         %Event{kind: "experience"} = source <-
           Repo.get_by(Event, id: event, world_id: world.id, experience_id: exp.id),
         true <- user in source.audience_users do
      key = "standing-report:" <> exp.id

      case Tx.receipt(world.id, key, user, request, event) do
        :new -> report_new(scope, world, exp, source, user, key, request)
        result -> result
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :unavailable}
    end
  end

  defp report_new(scope, world, exp, source, user, key, request) do
    with true <- exp.status == "active",
         true <- match?(%{status: "open"}, Repo.get(Genesis.Persistence.Window, exp.window_id)),
         {:ok, effect} <- Codec.load(source.event),
         true <- contribution?(effect),
         %Snapshot{} = snapshot <- Repo.get(Snapshot, source.snapshot_id),
         :ok <- Transfers.accessible(snapshot.id),
         {:ok, state} <- Snapshots.load(snapshot),
         true <- not is_nil(state.settlement),
         true <- effect.target_id == state.settlement["representative_id"],
         {:ok, network} <- WorldNetwork.view(scope, world.id),
         institution =
           NetworkCatalog.institution_id(world.id, state.zone_id, state.settlement["id"]),
         true <- Enum.any?(network.institutions, &(&1.id == institution and &1.registered)),
         resource = Worlds.named_id(["standing", institution, effect.actor_id]),
         {:ok, row, before} <-
           claim(world, exp, institution, effect.actor_id, resource, network.revision),
         {:ok, next} <- Standing.report(before, source.core_event_id, source.audience_users) do
      result = save_report(world, exp, row, before, next, source, effect, user)
      Tx.remember!(world.id, key, user, request, source.id, result)
      {:ok, result}
    else
      {:error, _} = error -> error
      _ -> {:error, :report_unavailable}
    end
  end

  defp contribution?(%{
         type: "offer",
         actor_id: actor,
         target_id: target,
         accounting: %{"kind" => "transfer", "flows" => flows}
       }),
       do: Enum.any?(flows, &(&1["from"] == actor and &1["to"] == target and &1["quantity"] > 0))

  defp contribution?(_effect), do: false

  defp claim(world, exp, institution, actor, resource, network_revision) do
    dependency =
      Repo.get_by(GlobalDependency,
        world_id: world.id,
        generation: world.generation,
        resource_id: resource
      )

    row =
      Repo.get_by(Record,
        world_id: world.id,
        generation: world.generation,
        scope_key: exp.id,
        resource_id: resource
      )

    cond do
      dependency && dependency.experience_id != exp.id ->
        {:error, :global_claimed}

      row && dependency ->
        existing_claim(world, row, dependency, network_revision)

      row || dependency ->
        {:error, :corrupt_global_state}

      true ->
        with :ok <- capacity(world, exp),
             {:ok, base} <- published(world.id, world.generation, resource) do
          Tx.insert!(GlobalDependency, %{
            world_id: world.id,
            generation: world.generation,
            experience_id: exp.id,
            resource_id: resource,
            mode: "write",
            base_digest: Codec.digest(base),
            network_revision: network_revision
          })

          row =
            Tx.insert!(Record, %{
              world_id: world.id,
              generation: world.generation,
              experience_id: exp.id,
              scope_key: exp.id,
              resource_id: resource,
              institution_id: institution,
              actor_id: actor,
              base: base,
              data: base,
              digest: Codec.digest(base),
              revision: 0
            })

          {:ok, row, base}
        end
    end
  end

  defp existing_claim(world, row, dependency, network_revision) do
    with {:ok, base} <- published(world.id, world.generation, row.resource_id),
         true <-
           row.base == base and dependency.base_digest == Codec.digest(base) and
             dependency.network_revision == network_revision and dependency.mode == "write" do
      validate_row(row)
    else
      _ -> {:error, :stale_global_dependencies}
    end
  end

  defp capacity(world, exp) do
    count =
      Repo.aggregate(
        from(r in Record, where: r.world_id == ^world.id and r.experience_id == ^exp.id),
        :count
      )

    if count < 200, do: :ok, else: {:error, :capacity_limit}
  end

  defp save_report(_world, _exp, row, before, before, _source, _effect, _user),
    do: %{
      "resource_id" => row.resource_id,
      "standing" => before["standing"],
      "status" => "already_reported"
    }

  defp save_report(world, exp, row, before, next, source, effect, user) do
    Tx.update!(row, %{data: next, digest: Codec.digest(next), revision: row.revision + 1})

    event =
      Tx.event!(world, %{
        scope_key: "standing:" <> exp.id <> ":" <> row.resource_id,
        kind: "experience",
        experience_id: exp.id,
        campaign_id: exp.campaign_id,
        principal_id: user,
        core_event_id: Worlds.named_id([exp.id, "report", source.id]),
        audience_users: next["audience_users"],
        event:
          Codec.dump!(%{
            "before_digest" => Codec.digest(before),
            "after_data" => next,
            type: "standing_reported",
            actor_id: effect.actor_id,
            target_id: row.institution_id,
            source_ids: [source.core_event_id],
            occurred_at: effect.occurred_at,
            result: %{"standing" => next["standing"], "resource_id" => row.resource_id}
          })
      })

    %{
      "resource_id" => row.resource_id,
      "standing" => next["standing"],
      "status" => "working",
      "event_id" => event.id
    }
  end

  @spec published(world :: String.t(), generation :: integer(), resource :: String.t()) :: term()
  def published(world, generation, resource) do
    case Repo.get_by(Record,
           world_id: world,
           generation: generation,
           scope_key: "published",
           resource_id: resource
         ) do
      nil -> {:ok, Standing.new()}
      row -> with {:ok, _, data} <- validate_row(row), do: {:ok, data}
    end
  end

  @spec validate_row(row :: map()) :: term()
  def validate_row(row) do
    if Scope.id?(row.actor_id) and Scope.id?(row.institution_id) and
         row.resource_id == Worlds.named_id(["standing", row.institution_id, row.actor_id]) and
         row.scope_key == (row.experience_id || "published") and
         Standing.valid?(row.data) and Standing.valid?(row.base) and
         row.digest == Codec.digest(row.data),
       do: {:ok, row, row.data},
       else: {:error, :corrupt_global_state}
  end

  @spec view(scope :: term(), world :: String.t(), experience :: String.t() | nil) :: term()
  def view(scope, world, exp \\ nil) do
    Tx.run(world, &read_view(scope, &1, exp))
  end

  defp read_view(scope, world, exp) do
    with :ok <- Access.world(scope, world.id),
         {:ok, user} <- Access.user_id(scope),
         :ok <- visible_experience(scope, world.id, exp) do
      key = exp || "published"

      rows =
        Repo.all(
          from r in Record,
            where:
              r.world_id == ^world.id and r.generation == ^world.generation and
                r.scope_key == ^key,
            limit: 201
        )

      if length(rows) <= 200 and Enum.all?(rows, &match?({:ok, _, _}, validate_row(&1))) do
        {:ok,
         for(
           r <- rows,
           user in r.data["audience_users"],
           do: %{
             id: r.id,
             resource_id: r.resource_id,
             institution_id: r.institution_id,
             actor_id: r.actor_id,
             standing: r.data["standing"],
             relief_supported: r.data["relief_supported"],
             source_ids: r.data["sources"],
             status: if(exp, do: "Working", else: "Published")
           }
         )}
      else
        {:error, :corrupt_global_state}
      end
    end
  end

  defp visible_experience(_scope, _world, nil), do: :ok

  defp visible_experience(scope, world, exp),
    do: with({:ok, _} <- Experiences.get(scope, world, exp), do: :ok)
end
