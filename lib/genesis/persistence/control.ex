defmodule Genesis.Persistence.Control do
  @moduledoc "Transactional pause/resume/seal operations invoked by the owning Zone."
  alias Genesis.Core.{Scope, State}
  alias Genesis.Experiences

  alias Genesis.Persistence.{
    Access,
    Codec,
    Footprints,
    Seals,
    Snapshot,
    Snapshots,
    Transfers,
    Transition,
    Tx
  }

  alias Genesis.Repo
  alias Genesis.Time.{Clock, Deadline}

  @spec change(
          scope :: term(),
          snapshot_id :: String.t(),
          before :: State.t(),
          action :: atom(),
          revision :: integer(),
          request :: String.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def change(scope, snapshot_id, before, action, revision, request, opts) do
    Tx.run(before.scope.world_id, fn world ->
      with {:ok, exp} <- Experiences.get(scope, world.id, before.scope.id, ["gm"]),
           {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(request),
           :ok <- footprint_available(exp) do
        snapshot = Repo.get!(Snapshot, snapshot_id)
        payload = {"status", action, revision}

        operation = %{
          action: action,
          revision: revision,
          user: user,
          request: request,
          payload: payload
        }

        restore_or_update(world, exp, snapshot, before, operation, opts)
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_request}
      end
    end)
  end

  defp footprint_available(exp) do
    with {:ok, rows} <- Footprints.snapshots(exp) do
      if Enum.any?(rows, &(Transfers.accessible(&1.id) != :ok)),
        do: {:error, :transfer_busy},
        else: :ok
    end
  end

  defp restore_or_update(world, exp, snapshot, before, operation, opts) do
    case Tx.receipt(
           world.id,
           snapshot.scope_key,
           operation.user,
           operation.request,
           operation.payload
         ) do
      {:ok, result} ->
        with {:ok, scene} <- Snapshots.load(snapshot), do: {:ok, %{scene: scene, result: result}}

      :new ->
        update(world, exp, snapshot, before, operation, opts)

      error ->
        error
    end
  end

  defp update(world, exp, snapshot, before, operation, opts) do
    %{action: action, revision: revision, user: user, request: request, payload: payload} =
      operation

    clock = Keyword.get(opts, :clock, Clock.system())

    with true <- before.revision == revision and snapshot.digest == Codec.digest(before),
         {:ok, status} <- next_status(exp.status, action),
         {:ok, deadline} <- Deadline.change(exp.deadline, action, clock) do
      next = if action == :resume, do: State.resume(before), else: State.pause(before)
      next = %{next | revision: before.revision + 1}
      {:ok, transition} = Transition.between(before, next)
      snapshot = Snapshots.save!(snapshot, next)

      exp =
        Tx.update!(exp, %{
          status: status,
          revision: exp.revision + 1,
          deadline: deadline
        })

      Tx.event!(
        world,
        %{
          snapshot_id: snapshot.id,
          scope_key: snapshot.scope_key,
          kind: "experience",
          experience_id: exp.id,
          campaign_id: exp.campaign_id,
          principal_id: user,
          audience_users: [user],
          event:
            Codec.dump!(%{
              type: "experience_#{status}",
              occurred_at: next.time.value,
              result: %{"status" => status}
            }),
          transition: transition
        },
        clock
      )

      if action == :ready, do: seal!(exp)

      result = %{"experience_id" => exp.id, "status" => status, "revision" => next.revision}
      Tx.remember!(world.id, snapshot.scope_key, user, request, payload, result)
      {:ok, %{scene: next, result: result}}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :stale_revision}
    end
  end

  defp next_status("active", :pause), do: {:ok, "paused"}
  defp next_status("paused", :resume), do: {:ok, "active"}
  defp next_status(status, :ready) when status in ["active", "paused"], do: {:ok, "ready"}
  defp next_status(_status, _action), do: {:error, :invalid_status_transition}

  defp seal!(exp) do
    case Seals.capture(exp) do
      {:ok, completion} -> Tx.update!(exp, %{completion: completion})
      {:error, reason} -> Repo.rollback(reason)
    end
  end
end
