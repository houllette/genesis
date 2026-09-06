defmodule Genesis.Persistence.Incorporation do
  @moduledoc "Atomic whole-footprint publication with durable preparation, cache fences and receipt recovery."
  import Ecto.Query
  alias Genesis.Core.Scope
  alias Genesis.Persistence.Access
  alias Genesis.Persistence.Actions
  alias Genesis.Persistence.Claim
  alias Genesis.Persistence.Codec
  alias Genesis.Persistence.Experience
  alias Genesis.Persistence.Footprints
  alias Genesis.Persistence.GlobalPublication
  alias Genesis.Persistence.IncorporationPlan
  alias Genesis.Persistence.Publication
  alias Genesis.Persistence.Snapshot
  alias Genesis.Persistence.Snapshots
  alias Genesis.Persistence.TimedPlan
  alias Genesis.Persistence.TimedPublication
  alias Genesis.Persistence.Transition
  alias Genesis.Persistence.Tx
  alias Genesis.Persistence.Window
  alias Genesis.Persistence.World
  alias Genesis.Repo
  alias Genesis.Worlds

  @spec prepare(scope :: term(), world_id :: String.t(), experience_id :: String.t()) :: term()
  def prepare(scope, world, experience),
    do: Tx.run(world, &IncorporationPlan.prepare(scope, &1, experience))

  @spec receipt(
          scope :: term(),
          world :: String.t(),
          preview :: String.t(),
          request :: String.t()
        ) :: term()
  def receipt(scope, world, preview, request) do
    Tx.run(world, fn _ ->
      with :ok <- Access.world(scope, world, ["steward"]),
           {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(preview) and Scope.id?(request) do
        wrap_new(Tx.receipt(world, "incorporation", user, request, %{"preview_id" => preview}))
      else
        false -> {:error, :invalid_request}
        error -> error
      end
    end)
    |> unwrap_new()
  end

  defp unwrap_new({:ok, :new}), do: :new
  defp unwrap_new(result), do: result
  defp wrap_new(:new), do: {:ok, :new}
  defp wrap_new(result), do: result

  @spec begin(scope :: term(), world :: String.t(), prepared :: map(), request :: String.t()) ::
          term()
  def begin(scope, world, prepared, request) do
    Tx.run(world, fn record ->
      with {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(request),
           {:ok, current} <- reprepare(scope, record, prepared.manifest, prepared.experience.id),
           true <- current.id == prepared.id,
           false <-
             Repo.exists?(
               from t in Genesis.Persistence.Transfer,
                 where: t.world_id == ^world and t.status in ["prepared", "committed"]
             ) do
        id = Worlds.named_id([world, "publication", user, request])

        attrs = %{
          world_id: world,
          experience_id: current.experience.id,
          principal_id: user,
          generation: record.generation,
          preview_id: current.id,
          request_id: request,
          manifest: current.manifest,
          status: "prepared",
          result: %{}
        }

        prepare_operation(Repo.get(Publication, id), id, attrs)
      else
        {:error, _} = error -> error
        _ -> {:error, :stale_preview}
      end
    end)
  end

  defp prepare_operation(nil, id, attrs),
    do: {:ok, Tx.insert!(Publication, Map.put(attrs, :id, id))}

  defp prepare_operation(
         %{status: "aborted", preview_id: preview} = old,
         _id,
         %{preview_id: preview} = attrs
       ),
       do: {:ok, Tx.update!(old, attrs)}

  defp prepare_operation(_old, _id, _attrs), do: {:error, :request_conflict}

  @spec publish(scope :: term(), operation :: map(), opts :: keyword()) :: term()
  def publish(scope, op, opts) do
    Tx.run(
      op.world_id,
      fn world ->
        with %Publication{status: "prepared"} = current <- Repo.get(Publication, op.id),
             {:ok, user} <- Access.user_id(scope),
             true <- current.principal_id == user and current.generation == world.generation,
             {:ok, prepared} <-
               reprepare(scope, world, current.manifest, current.experience_id, op.id),
             true <- prepared.id == current.preview_id and prepared.manifest == current.manifest do
          result = commit(world, user, prepared, current.request_id)
          Tx.update!(current, %{status: "committed", result: result})
          Actions.fault(opts, :before_commit)
          {:ok, result}
        else
          {:error, _} = error -> error
          _ -> {:error, :stale_preview}
        end
      end,
      op.id
    )
  end

  defp reprepare(scope, world, manifest, experience, operation \\ nil)

  defp reprepare(scope, world, %{"preparation_id" => id}, _experience, _operation),
    do: TimedPlan.prepare(scope, world, id)

  defp reprepare(scope, world, _manifest, experience, operation),
    do: IncorporationPlan.prepare(scope, world, experience, operation)

  defp commit(world, user, %{preparation: _} = prepared, request),
    do: TimedPublication.commit(world, user, prepared, request)

  defp commit(world, user, prepared, request) do
    Snapshots.reindex!(
      Enum.map(prepared.zones, & &1.published),
      Enum.map(prepared.zones, & &1.candidate)
    )

    rows = Enum.map(prepared.zones, &Snapshots.save!(&1.published_snapshot, &1.candidate))

    events =
      publish_events(world, user, prepared) ++
        GlobalPublication.publish!(
          world,
          prepared.global,
          prepared.mapping,
          user
        )

    exp = prepared.experience
    Tx.update!(exp, %{status: "incorporated", revision: exp.revision + 1})
    Tx.update!(Repo.get!(Window, exp.window_id), %{status: "closed"})

    Repo.delete_all(
      from c in Claim,
        where:
          c.experience_id == ^exp.id and c.world_id == ^world.id and
            c.generation == ^world.generation
    )

    Tx.update!(Repo.get!(World, world.id), %{revision: world.revision + 1})
    Enum.each(rows, &Snapshots.checkpoint!(&1, List.last(events).cursor))

    result = %{
      "snapshot_id" => Enum.find(rows, &(&1.zone_id == exp.zone_id)).id,
      "snapshot_ids" => Enum.map(rows, & &1.id),
      "zone_ids" => Enum.map(rows, & &1.zone_id),
      "experience_id" => exp.id,
      "status" => "incorporated",
      "event_ids" => Enum.map(events, & &1.id),
      "world_time" => world.fictional_time
    }

    Tx.remember!(world.id, "incorporation", user, request, %{"preview_id" => prepared.id}, result)
    result
  end

  defp publish_events(world, user, prepared) do
    by_snapshot = Map.new(prepared.zones, &{&1.working_snapshot.id, &1})

    {events, seen} =
      Enum.map_reduce(prepared.sources, MapSet.new(), fn source, seen ->
        zone = Map.fetch!(by_snapshot, source.snapshot_id)
        {:ok, event} = Codec.load(source.event)
        id = Map.fetch!(prepared.mapping, source.core_event_id)

        event =
          event
          |> Map.put(:id, id)
          |> Map.put(:scope, zone.candidate.scope)
          |> Map.put(:revision, zone.candidate.revision)
          |> Map.put(:source_ids, Enum.map(event.source_ids, &Map.get(prepared.mapping, &1, &1)))

        delta =
          if MapSet.member?(seen, source.snapshot_id),
            do: %{"format" => 1, "unchanged" => Codec.digest(zone.candidate)},
            else: transition(zone)

        row =
          Tx.event!(world, %{
            scope_key: zone.published_snapshot.scope_key,
            snapshot_id: zone.published_snapshot.id,
            kind: "world",
            principal_id: user,
            actor_id: source.actor_id,
            campaign_id: source.campaign_id,
            core_event_id: id,
            source_event_id: source.id,
            audience_users: source.audience_users,
            event: Codec.dump!(event),
            transition: delta
          })

        {row, MapSet.put(seen, source.snapshot_id)}
      end)

    empty =
      prepared.zones
      |> Enum.reject(&MapSet.member?(seen, &1.working_snapshot.id))
      |> Enum.map(fn zone ->
        Tx.event!(world, %{
          scope_key: zone.published_snapshot.scope_key,
          snapshot_id: zone.published_snapshot.id,
          kind: "world",
          principal_id: user,
          audience_users: [user],
          transition: transition(zone),
          event: Codec.dump!(%{type: "empty_experience_incorporated", result: %{}})
        })
      end)

    events ++ empty
  end

  defp transition(zone) do
    {:ok, delta} = Transition.between(zone.published, zone.candidate)
    delta
  end

  @spec read(world :: String.t(), operation :: String.t(), snapshot :: String.t()) :: term()
  def read(world, operation, snapshot) do
    Tx.run(
      world,
      fn record ->
        with %Publication{world_id: ^world, status: status} = op <-
               Repo.get(Publication, operation),
             true <- status in ["prepared", "committed"] and op.generation == record.generation,
             true <- Enum.any?(op.manifest["zones"], &(&1["published_snapshot_id"] == snapshot)),
             %Snapshot{} = row <- Repo.get(Snapshot, snapshot),
             {:ok, scene} <- Snapshots.load(row) do
          {:ok, scene}
        else
          _ -> {:error, :stale_publication}
        end
      end,
      operation
    )
  end

  @spec finish(operation :: map()) :: term()
  def finish(op) do
    Tx.run(
      op.world_id,
      fn world ->
        with %Publication{status: "committed"} = current <- Repo.get(Publication, op.id),
             :ok <- committed?(world, current) do
          installed!(world, current)
          {:ok, current.result}
        else
          {:error, _} = error -> error
          _ -> {:error, :stale_publication}
        end
      end,
      op.id
    )
  end

  @doc "Only during cold World startup or after the World has stopped all affected published caches."
  @spec recover(world :: String.t()) :: term()
  def recover(world) do
    case Repo.one(
           from p in Publication,
             where: p.world_id == ^world and p.status in ["prepared", "committed"]
         ) do
      nil -> {:ok, :recovered}
      op -> recover_operation(op)
    end
  end

  defp recover_operation(op) do
    Tx.run(
      op.world_id,
      fn world ->
        current = Repo.get!(Publication, op.id)

        with :ok <- recoverable?(world, current) do
          recovered!(world, current)

          {:ok, :recovered}
        end
      end,
      op.id
    )
  end

  defp recoverable?(world, %{status: "prepared"} = op) do
    if world.generation == op.generation and world.revision == op.manifest["world_revision"] and
         snapshots_match?(op, "base_digest") and
         GlobalPublication.matches?(op, "base_digest"),
       do: :ok,
       else: {:error, :corrupt_publication}
  end

  defp recoverable?(world, op), do: committed?(world, op)

  defp recovered!(_world, %{status: "prepared"} = op), do: Tx.update!(op, %{status: "aborted"})
  defp recovered!(world, op), do: installed!(world, op)

  defp installed!(world, op) do
    Tx.update!(op, %{status: "installed"})

    Tx.event!(world, %{
      scope_key: "publication",
      kind: "world",
      principal_id: op.principal_id,
      audience_users: [op.principal_id],
      event: Codec.dump!(%{type: "publication_installed", result: %{"operation_id" => op.id}})
    })
  end

  defp committed?(world, op) do
    if world.generation == op.generation and world.revision == op.manifest["world_revision"] + 1 and
         snapshots_match?(op, "candidate_digest") and published_ownership?(op) and
         lifecycle_committed?(op) and
         GlobalPublication.matches?(op, "candidate_digest") and
         released?(op) and
         Tx.receipt(world.id, "incorporation", op.principal_id, op.request_id, %{
           "preview_id" => op.preview_id
         }) == {:ok, op.result}, do: :ok, else: {:error, :corrupt_publication}
  end

  defp released?(%{manifest: %{"format" => 8}}), do: true
  defp released?(op), do: GlobalPublication.released?(op.experience_id)

  defp lifecycle_committed?(%{manifest: %{"format" => 8}} = op),
    do:
      Repo.get!(World, op.world_id).fictional_time == op.manifest["target"] and
        TimedPublication.lifecycle_committed?(op)

  defp lifecycle_committed?(op) do
    case Repo.get(Experience, op.experience_id) do
      %{status: "incorporated", window_id: window} ->
        match?(%{status: "closed"}, Repo.get(Window, window)) and
          not Repo.exists?(from c in Claim, where: c.experience_id == ^op.experience_id)

      _ ->
        false
    end
  end

  defp published_ownership?(op) do
    rows = Enum.map(op.manifest["zones"], &Repo.get!(Snapshot, &1["published_snapshot_id"]))

    case Footprints.load(rows) do
      {:ok, pairs} -> Snapshots.check_index(Enum.map(pairs, &elem(&1, 1))) == :ok
      _ -> false
    end
  end

  defp snapshots_match?(op, field),
    do:
      Enum.all?(op.manifest["zones"], fn zone ->
        case Repo.get(Snapshot, zone["published_snapshot_id"]) do
          nil -> false
          row -> row.digest == zone[field] and match?({:ok, _}, Snapshots.load(row))
        end
      end)
end
