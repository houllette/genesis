defmodule Genesis.Persistence.Incorporation do
  @moduledoc "Bounded storage proof: one ready experience, one zone, zero elapsed time, source-linked atomic publication."
  import Ecto.Query
  alias Genesis.Core.Incorporation, as: Projection
  alias Genesis.Core.Scope

  alias Genesis.Persistence.{
    Access,
    Actions,
    Checkpoint,
    Claim,
    Codec,
    Event,
    Experience,
    Replay,
    Snapshot,
    Snapshots,
    Transition,
    Tx,
    Window,
    World
  }

  alias Genesis.{Experiences, Repo, Worlds}

  @spec prepare(scope :: term(), world_id :: String.t(), experience_id :: String.t()) ::
          {:ok, map()} | {:error, term()}
  def prepare(scope, world_id, experience_id),
    do: Tx.run(world_id, &prepare_locked(scope, &1, experience_id))

  defp prepare_locked(scope, world, id) do
    with :ok <- Access.world(scope, world.id, ["steward"]),
         {:ok, %{status: "ready"} = exp} <- Experiences.get(scope, world.id, id, ["gm"]),
         %Window{status: "open"} = window <- Repo.get(Window, exp.window_id),
         true <- window.base_revision == world.revision and window.generation == world.generation,
         true <-
           Repo.aggregate(from(e in Experience, where: e.window_id == ^window.id), :count) == 1,
         %Snapshot{} = working_snapshot <- Repo.get_by(Snapshot, experience_id: exp.id),
         {:ok, working} <- Snapshots.load(working_snapshot),
         :ok <- zero_duration(working),
         true <- exp.completion["snapshot_digest"] == working_snapshot.digest,
         base_checkpoint = Repo.get!(Checkpoint, exp.base_checkpoint_id),
         {:ok, published} <- Codec.load_state(base_checkpoint.state),
         %Snapshot{} = published_snapshot <- Repo.get(Snapshot, base_checkpoint.snapshot_id),
         true <- published_snapshot.digest == base_checkpoint.digest,
         working_checkpoint =
           Repo.one!(
             from c in Checkpoint,
               where: c.snapshot_id == ^working_snapshot.id,
               order_by: c.cursor,
               limit: 1
           ),
         {:ok, working_base} <- Codec.load_state(working_checkpoint.state),
         {:ok, ^working} <- Replay.restore(scope, world.id, working_checkpoint.id),
         :ok <- claims_match(world, exp, published),
         sources =
           Repo.all(
             from e in Event,
               where: e.experience_id == ^exp.id and not is_nil(e.actor_id),
               order_by: e.cursor
           ),
         true <- length(sources) <= 200,
         mapping =
           Map.new(
             sources,
             &{&1.core_event_id, Worlds.named_id(["incorporation", exp.id, &1.id])}
           ),
         {:ok, candidate} <- Projection.project(published, working_base, working, mapping) do
      manifest = %{
        "world_id" => world.id,
        "generation" => world.generation,
        "world_revision" => world.revision,
        "experience_id" => exp.id,
        "working_digest" => working_snapshot.digest,
        "base_digest" => base_checkpoint.digest,
        "sources" => Enum.map(sources, & &1.id),
        "target" => world.fictional_time
      }

      {:ok,
       %{
         manifest: manifest,
         id: Codec.digest(manifest),
         candidate: candidate,
         published: published,
         published_snapshot: published_snapshot,
         experience: exp,
         working_snapshot: working_snapshot,
         sources: sources,
         mapping: mapping
       }}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :incorporation_not_ready}
    end
  end

  @spec receipt(
          scope :: term(),
          world_id :: String.t(),
          preview_id :: String.t(),
          request :: String.t()
        ) :: {:ok, term()} | :new | {:error, atom()}
  def receipt(scope, world, preview, request) do
    with :ok <- Access.world(scope, world, ["steward"]),
         {:ok, user} <- Access.user_id(scope),
         true <- Scope.id?(preview) and Scope.id?(request) do
      Tx.receipt(world, "incorporation", user, request, %{"preview_id" => preview})
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_request}
    end
  end

  @spec publish(
          scope :: term(),
          world_id :: String.t(),
          prepared :: map(),
          request :: String.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def publish(scope, world, prepared, request, opts) do
    Tx.run(world, fn record ->
      with :ok <- Access.world(scope, world, ["steward"]),
           {:ok, user} <- Access.user_id(scope),
           {:ok, current} <- prepare_locked(scope, record, prepared.experience.id),
           true <- current.id == prepared.id,
           :new <- receipt(scope, world, prepared.id, request) do
        commit(record, user, current, request, opts)
      else
        {:ok, stored} -> {:ok, stored}
        {:error, _reason} = error -> error
        _ -> {:error, :stale_preview}
      end
    end)
  end

  defp commit(world, user, prepared, request, opts) do
    snapshot = Snapshots.save!(prepared.published_snapshot, prepared.candidate)
    {:ok, transition} = Transition.between(prepared.published, prepared.candidate)
    events = publish_events(world, user, prepared, transition)
    exp = prepared.experience
    Tx.update!(exp, %{status: "incorporated", revision: exp.revision + 1})
    Tx.update!(Repo.get!(Window, exp.window_id), %{status: "closed"})

    Repo.delete_all(
      from c in Claim,
        where:
          c.experience_id == ^exp.id and c.world_id == ^world.id and
            c.generation == ^world.generation
    )

    # event! updates cursor; do not overwrite it with the earlier locked copy.
    Tx.update!(Repo.get!(World, world.id), %{revision: world.revision + 1})
    Snapshots.checkpoint!(snapshot, List.last(events).cursor)

    result = %{
      "snapshot_id" => snapshot.id,
      "experience_id" => exp.id,
      "status" => "incorporated",
      "event_ids" => Enum.map(events, & &1.id),
      "world_time" => world.fictional_time
    }

    Tx.remember!(world.id, "incorporation", user, request, %{"preview_id" => prepared.id}, result)
    Actions.fault(opts, :before_commit)
    {:ok, result}
  end

  defp publish_events(world, user, %{sources: []} = prepared, transition) do
    [
      Tx.event!(world, %{
        scope_key: prepared.published_snapshot.scope_key,
        snapshot_id: prepared.published_snapshot.id,
        kind: "world",
        principal_id: user,
        audience_users: [user],
        transition: transition,
        event: Codec.dump!(%{type: "empty_experience_incorporated", result: %{}})
      })
    ]
  end

  defp publish_events(world, user, prepared, transition) do
    Enum.with_index(prepared.sources)
    |> Enum.map(fn {source, index} ->
      {:ok, event} = Codec.load(source.event)
      id = Map.fetch!(prepared.mapping, source.core_event_id)

      event =
        event
        |> Map.put(:id, id)
        |> Map.put(:scope, prepared.candidate.scope)
        |> Map.put(:source_ids, Enum.map(event.source_ids, &Map.get(prepared.mapping, &1, &1)))

      delta =
        if index == 0,
          do: transition,
          else: %{"format" => 1, "unchanged" => Codec.digest(prepared.candidate)}

      Tx.event!(world, %{
        scope_key: prepared.published_snapshot.scope_key,
        snapshot_id: prepared.published_snapshot.id,
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
    end)
  end

  defp zero_duration(%{elapsed: 0}), do: :ok
  defp zero_duration(_state), do: {:error, :time_reconciliation_unavailable}

  defp claims_match(world, exp, base) do
    expected =
      [{"zone", base.zone_id}] ++
        Enum.map(Map.keys(base.actors), &{"actor", &1}) ++
        Enum.map(Map.keys(base.items), &{"item", &1})

    actual =
      Repo.all(
        from c in Claim,
          where:
            c.world_id == ^world.id and c.generation == ^world.generation and
              c.experience_id == ^exp.id,
          select: {c.resource_kind, c.resource_id}
      )

    if Enum.sort(expected) == Enum.sort(actual), do: :ok, else: {:error, :stale_claims}
  end
end
