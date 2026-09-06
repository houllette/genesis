defmodule Genesis.Persistence.Control do
  @moduledoc "Transactional pause/resume/seal operations invoked by the owning Zone."
  alias Genesis.Core.LocalTime, as: TimeRules
  alias Genesis.Core.{Scope, State}
  alias Genesis.Experiences

  alias Genesis.Persistence.{
    Access,
    Actions,
    Codec,
    Footprints,
    LocalAdvance,
    LocalTime,
    Seals,
    Snapshot,
    Snapshots,
    Transfers,
    Transition,
    Tx
  }

  alias Genesis.Repo
  alias Genesis.Time.{Calendar, Clock, Deadline}
  alias Genesis.Worlds

  @spec change(
          scope :: term(),
          snapshot_id :: String.t(),
          before :: State.t(),
          action :: term(),
          revision :: integer(),
          request :: String.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def change(scope, snapshot_id, before, action, revision, request, opts) do
    Tx.run(before.scope.world_id, fn world ->
      with {:ok, exp} <- Experiences.get(scope, world.id, before.scope.id, ["gm"]),
           {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(request),
           {:ok, _encoded} <- Codec.dump(action),
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
         true <- match?(%{status: "open"}, Repo.get(Genesis.Persistence.Window, exp.window_id)),
         {:ok, status} <- next_status(exp.status, action),
         {:ok, next, details} <- prepare_change(world, exp, before, action),
         {:ok, before, next} <-
           scheduled_steps(world, exp, snapshot, before, next, operation, clock),
         {:ok, deadline} <- change_deadline(exp.deadline, action, clock) do
      {:ok, transition} = Transition.between(before, next)
      snapshot = Snapshots.save!(snapshot, next)

      exp =
        Tx.update!(exp, %{
          status: status,
          revision: exp.revision + 1,
          deadline: deadline
        })

      completion_id = Worlds.named_id(["experience-control", exp.id, user, request])

      Tx.event!(
        world,
        %{
          snapshot_id: snapshot.id,
          scope_key: snapshot.scope_key,
          kind: "experience",
          experience_id: exp.id,
          campaign_id: exp.campaign_id,
          principal_id: user,
          core_event_id: completion_id,
          audience_users: [user],
          event:
            Codec.dump!(%{
              type:
                if(match?({:elapse, _}, action), do: "scene_time", else: "experience_#{status}"),
              occurred_at: next.time.value,
              time: TimeRules.contribution(before, next),
              result: Map.put(details, "status", status)
            }),
          transition: transition
        },
        clock
      )

      seal!(exp, action, completion_id)

      result = %{"experience_id" => exp.id, "status" => status, "revision" => next.revision}
      Tx.remember!(world.id, snapshot.scope_key, user, request, payload, result)
      Actions.fault(opts, :control_before_commit)
      {:ok, %{scene: next, result: result}}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :stale_revision}
    end
  end

  defp scheduled_steps(
         world,
         exp,
         snapshot,
         before,
         next,
         %{action: {:elapse, _}, user: user},
         clock
       ) do
    with {:ok, current, next, steps} <- LocalAdvance.prepare(world, exp, before, next.time.value) do
      LocalAdvance.save!(world, exp, snapshot, steps, user, clock)
      {:ok, current, next}
    end
  end

  defp scheduled_steps(_world, _exp, _snapshot, before, next, _operation, _clock),
    do: {:ok, before, next}

  defp next_status("active", :pause), do: {:ok, "paused"}
  defp next_status("paused", :resume), do: {:ok, "active"}
  defp next_status("active", {:elapse, _}), do: {:ok, "active"}

  defp next_status(status, {:finish, %{} = declaration}) when status in ["active", "paused"],
    do: {:ok, if(declaration["review_required"] == true, do: "needs_review", else: "ready")}

  defp next_status(status, :ready) when status in ["active", "paused"], do: {:ok, "ready"}
  defp next_status(_status, _action), do: {:error, :invalid_status_transition}

  defp seal!(exp, :ready, _id), do: save_seal!(exp, Seals.capture(exp))

  defp seal!(exp, {:finish, declaration}, id),
    do: save_seal!(exp, Seals.capture_completion(exp, declaration, id))

  defp seal!(_exp, _action, _id), do: :ok

  defp save_seal!(exp, result) do
    case result do
      {:ok, completion} -> Tx.update!(exp, %{completion: completion})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp prepare_change(world, exp, before, {:elapse, %{"reason" => reason} = amount})
       when map_size(amount) == 3 do
    with true <- TimeRules.reason?(reason),
         {:ok, summary} <- LocalTime.summary(exp),
         {:ok, seconds} <-
           Calendar.duration(
             %{before.time | value: before.time.value + summary.elapsed_seconds - before.elapsed},
             Map.delete(amount, "reason"),
             world.calendar
           ),
         {:ok, next} <-
           TimeRules.elapse(before, summary.elapsed_seconds - before.elapsed + seconds),
         :ok <- LocalTime.admit(exp, before, next, true) do
      {:ok, next,
       %{
         "reason" => reason,
         "duration_input" => amount,
         "resolved_seconds" => seconds,
         "calendar" => world.calendar,
         "policy" => "local-time-v1"
       }}
    else
      false -> {:error, :invalid_local_time}
      error -> error
    end
  end

  defp prepare_change(_world, _exp, _before, {:elapse, _}), do: {:error, :invalid_local_time}

  defp prepare_change(_world, exp, before, {:finish, declaration}) do
    with {:ok, summary} <- LocalTime.summary(exp),
         {:ok, declaration} <- TimeRules.declaration(declaration, summary.elapsed_seconds),
         {:ok, basis} <- Seals.basis(exp),
         true <- basis == declaration["basis"] do
      {:ok, %{State.pause(before) | revision: before.revision + 1},
       %{"declaration" => declaration}}
    else
      false -> {:error, :stale_completion}
      error -> error
    end
  end

  defp prepare_change(_world, _exp, before, action) do
    next = if action == :resume, do: State.resume(before), else: State.pause(before)
    {:ok, %{next | revision: before.revision + 1}, %{}}
  end

  defp change_deadline(saved, {:elapse, _}, _clock), do: {:ok, saved}
  defp change_deadline(saved, {:finish, _}, clock), do: Deadline.change(saved, :ready, clock)
  defp change_deadline(saved, action, clock), do: Deadline.change(saved, action, clock)
end
