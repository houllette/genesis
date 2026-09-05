defmodule Genesis.Persistence.Actions do
  @moduledoc "Atomic snapshot, event, receipt and outbox persistence beneath the sole Zone writer."
  import Ecto.Query
  alias Genesis.Core.State

  alias Genesis.Persistence.{
    Authority,
    Codec,
    Event,
    Receipt,
    Snapshot,
    Snapshots,
    Transfers,
    Transition,
    Tx
  }

  alias Genesis.Repo
  alias Genesis.Time.Clock

  @spec receipt(principal :: map(), id :: String.t(), payload :: term()) ::
          {:ok, map()} | :new | {:error, atom()}
  def receipt(principal, id, payload) do
    with {:ok, _current} <- Authority.current(principal) do
      Tx.receipt(
        principal.scope.world_id,
        Snapshots.key(principal.scope),
        principal.user_id,
        id,
        binding(principal, payload)
      )
    end
  end

  @spec commit(
          principal :: map(),
          before :: map(),
          next :: map(),
          receipt :: map(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def commit(principal, before, next, receipt, opts \\ []) do
    Tx.run(principal.scope.world_id, fn world ->
      with {:ok, %{status: :active} = current} <- Authority.current(principal),
           true <- current.snapshot_id == principal.snapshot_id,
           snapshot = Repo.get!(Snapshot, principal.snapshot_id),
           :ok <- Transfers.accessible(snapshot.id),
           true <- snapshot.digest == Codec.digest(before),
           :ok <- capacity(next),
           {:ok, _validated} <- State.restore(next),
           :ok <- Snapshots.compatible(world, next),
           {:ok, transition} <- Transition.between(before, next) do
        commit_new(world, snapshot, principal, next, receipt, transition, opts)
      else
        {:error, _reason} = error -> error
        false -> {:error, :stale_snapshot}
        _ -> {:error, :paused}
      end
    end)
  end

  defp capacity(next) do
    count =
      Repo.aggregate(
        from(e in Event, where: e.experience_id == ^next.scope.id and not is_nil(e.actor_id)),
        :count
      )

    if count < 200 and length(next.events) <= 200, do: :ok, else: {:error, :capacity_limit}
  end

  defp commit_new(world, snapshot, principal, next, receipt, transition, opts) do
    payload = binding(principal, receipt.payload)

    case Tx.receipt(world.id, snapshot.scope_key, principal.user_id, receipt.id, payload) do
      :new ->
        Snapshots.save!(snapshot, next)
        [effect] = receipt.effects

        event =
          Tx.event!(
            world,
            %{
              snapshot_id: snapshot.id,
              scope_key: snapshot.scope_key,
              kind: "experience",
              campaign_id: principal.campaign_id,
              experience_id: principal.scope.id,
              principal_id: principal.user_id,
              actor_id: principal.actor_id,
              core_event_id: effect.id,
              event: Codec.dump!(provenance(effect, principal, receipt.payload)),
              transition: transition,
              audience_users: Authority.audience_users(principal, effect)
            },
            Keyword.get(opts, :clock, Clock.system())
          )

        result = Map.put(receipt, :event_ids, [event.id])
        Tx.remember!(world.id, snapshot.scope_key, principal.user_id, receipt.id, payload, result)
        fault(opts, :before_commit)
        {:ok, result}

      {:ok, recorded} ->
        {:ok, recorded}

      error ->
        error
    end
  end

  @spec fault(opts :: keyword(), stage :: atom()) :: :ok
  def fault(opts, stage) do
    case Keyword.get(opts, :fault) do
      nil -> :ok
      fun -> fun.(stage)
    end
  end

  @spec step_id(plan_id :: String.t(), index :: non_neg_integer()) :: String.t()
  def step_id(plan, index), do: "step-" <> Codec.digest([plan, index])

  @spec previous_step(principal :: map(), plan_id :: String.t(), index :: non_neg_integer()) ::
          :ok | {:error, atom()}
  def previous_step(_principal, _plan, 0), do: :ok

  def previous_step(principal, plan, index) do
    prior =
      Repo.get_by(Receipt,
        world_id: principal.scope.world_id,
        scope_key: Snapshots.key(principal.scope),
        principal_id: principal.user_id,
        request_id: step_id(plan, index - 1)
      )

    with %Receipt{} <- prior,
         {:ok, {campaign, actor, scope, {:step, ^plan, previous, _payload}}} <-
           Codec.load(prior.payload),
         true <-
           previous == index - 1 and campaign == principal.campaign_id and
             actor == principal.actor_id and scope == principal.scope do
      :ok
    else
      _ -> {:error, :earlier_step_missing}
    end
  end

  defp binding(principal, payload),
    do: {principal.campaign_id, principal.actor_id, principal.scope, payload}

  defp provenance(effect, principal, payload) do
    effect
    |> Map.put(:operator_id, principal.user_id)
    |> Map.put(:participants, [principal.actor_id])
    |> Map.put(:causal_parent_ids, effect.source_ids)
    |> Map.put(:causal_root_id, List.first(effect.source_ids) || effect.id)
    |> Map.put(:affected_ids, [effect.actor_id, effect.target_id] |> Enum.uniq())
    |> plan_provenance(payload)
  end

  defp plan_provenance(effect, {:step, plan, index, _payload}),
    do: effect |> Map.put(:plan_id, plan) |> Map.put(:step_index, index)

  defp plan_provenance(effect, _payload), do: effect
end
