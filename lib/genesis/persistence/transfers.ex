defmodule Genesis.Persistence.Transfers do
  @moduledoc "Durable same-scope transfer decisions. No live-process callback occurs inside a transaction."
  import Ecto.Query
  alias Genesis.Core.Companions
  alias Genesis.Core.Network
  alias Genesis.Core.Scene
  alias Genesis.Core.Scope
  alias Genesis.Core.Transfer
  alias Genesis.Experiences
  alias Genesis.Persistence.Actions
  alias Genesis.Persistence.Authority
  alias Genesis.Persistence.Codec
  alias Genesis.Persistence.Event
  alias Genesis.Persistence.Footprints
  alias Genesis.Persistence.Reservation
  alias Genesis.Persistence.Snapshot
  alias Genesis.Persistence.Snapshots
  alias Genesis.Persistence.Transfer, as: Operation
  alias Genesis.Persistence.TransferRecovery
  alias Genesis.Persistence.Transition
  alias Genesis.Persistence.Tx
  alias Genesis.Repo
  alias Genesis.WorldNetwork
  alias Genesis.Worlds

  @spec preview(
          scope :: term(),
          world :: String.t(),
          experience :: String.t(),
          actor :: String.t(),
          destination :: String.t(),
          exchange :: map() | nil
        ) :: term()
  def preview(scope, world, exp, actor, destination, exchange \\ nil) do
    Tx.run(world, fn world ->
      with {:ok, plan} <- plan(scope, world, exp, actor, destination, exchange) do
        {:ok,
         %{
           token: plan.token,
           actor_id: actor,
           from: plan.source.zone_id,
           to: destination,
           exchange: exchange,
           party_size: plan.party_size,
           exchange_summary: exchange_summary(plan, actor, exchange)
         }}
      end
    end)
  end

  defp exchange_summary(_plan, _actor, nil), do: nil

  defp exchange_summary(plan, actor, exchange) do
    {:ok, _, arriving} = Transfer.move(plan.source, plan.destination, actor)

    {:ok, proposal} =
      Scene.propose(
        arriving,
        actor,
        %{
          type: exchange["type"],
          target_id: exchange["target_id"],
          quantity: exchange["quantity"]
        },
        "summary"
      )

    proposal.terms["summary"]
  end

  @spec valid_token?(token :: term()) :: boolean()
  def valid_token?(token) when is_map(token),
    do:
      Enum.sort(Map.keys(Map.delete(token, "exchange"))) ==
        ~w(destination_revision from generation network_revision source_revision to) and
        Transfer.valid_exchange?(token["exchange"]) and
        Enum.all?(~w(from to), &Scope.id?(token[&1])) and
        Enum.all?(
          ~w(generation network_revision source_revision destination_revision),
          &(is_integer(token[&1]) and token[&1] >= 0)
        )

  def valid_token?(_token), do: false

  @spec operation_id(
          world :: String.t(),
          exp :: String.t(),
          user :: String.t(),
          request :: String.t(),
          generation :: integer()
        ) :: String.t()
  def operation_id(world, exp, user, request, generation),
    do: Worlds.named_id([world, generation, exp, user, "travel", request])

  @spec begin(
          scope :: term(),
          world :: String.t(),
          exp :: String.t(),
          actor :: String.t(),
          token :: map(),
          request :: String.t()
        ) :: term()
  def begin(scope, world, exp, actor, token, request) do
    Tx.run(world, fn world ->
      with true <- valid_token?(token) and Scope.id?(request),
           true <- token["generation"] == world.generation,
           {:ok, principal, _} <- Authority.principal(scope, world.id, exp, actor) do
        id = operation_id(world.id, exp, principal.user_id, request, world.generation)
        payload = {principal.campaign_id, actor, token}

        restore_or_prepare(
          Repo.get(Operation, id),
          scope,
          world,
          principal,
          token,
          request,
          id,
          payload
        )
      else
        false -> {:error, :invalid_transfer}
        error -> error
      end
    end)
  end

  defp restore_or_prepare(nil, scope, world, principal, token, request, id, payload),
    do: prepare(scope, world, principal, token, request, id, payload, nil)

  defp restore_or_prepare(op, scope, world, principal, token, request, id, payload) do
    cond do
      op.payload != Codec.dump!(payload) -> {:error, :request_conflict}
      op.status == "installed" -> {:ok, {:done, op.result}}
      op.status == "prepared" -> {:error, :transfer_busy}
      op.status == "aborted" -> prepare(scope, world, principal, token, request, id, payload, op)
      true -> {:error, :recovery_required}
    end
  end

  defp plan(scope, world, exp_id, actor, destination, exchange) do
    with {:ok, exp} <- Experiences.get(scope, world.id, exp_id),
         {:ok, principal, source_row} <- Authority.principal(scope, world.id, exp_id, actor),
         true <-
           exp.status == "active" and principal.status == :active and actor in exp.participants,
         :ok <- accessible(source_row.id),
         {:ok, source} <- Snapshots.load(source_row),
         %{kind: :pc} <- source.actors[actor],
         {:ok, party} <- Companions.party(source, actor),
         {:ok, network} <- WorldNetwork.view(scope, world.id),
         :ok <-
           Network.assess(
             %{"connections" => network.connections},
             source.zone_id,
             destination,
             length(party)
           ),
         {:ok, footprint} <- Footprints.snapshots(exp),
         {:ok, states} <- Footprints.load(footprint),
         true <- source.elapsed == Enum.max(Enum.map(states, fn {_, scene} -> scene.elapsed end)),
         {:ok, dest_row, dest} <- Footprints.destination(world, exp, source, destination),
         true <- not is_nil(dest_row) or exp.start_offset == 0,
         :ok <- if(dest_row, do: accessible(dest_row.id), else: :ok),
         {:ok, _, _} <- Transfer.execute(source, dest, actor, exchange, "preview") do
      token = %{
        "generation" => world.generation,
        "network_revision" => network.revision,
        "from" => source.zone_id,
        "to" => destination,
        "source_revision" => source.revision,
        "destination_revision" => dest.revision
      }

      token = if exchange, do: Map.put(token, "exchange", exchange), else: token

      {:ok,
       %{
         exp: exp,
         principal: principal,
         source_row: source_row,
         destination_row: dest_row,
         source: source,
         destination: dest,
         party_size: length(party),
         token: token
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :unavailable}
    end
  end

  defp prepare(scope, world, principal, token, request, id, payload, old) do
    with {:ok, plan} <-
           plan(
             scope,
             world,
             principal.scope.id,
             principal.actor_id,
             token["to"],
             token["exchange"]
           ),
         true <- plan.token == token,
         :ok <- capacity(plan.exp.id),
         {:ok, dest_row} <- destination_row(world, plan) do
      attrs = %{
        id: id,
        world_id: world.id,
        generation: world.generation,
        experience_id: plan.exp.id,
        principal_id: principal.user_id,
        actor_id: principal.actor_id,
        source_snapshot_id: plan.source_row.id,
        destination_snapshot_id: dest_row.id,
        request_id: request,
        payload: Codec.dump!(payload),
        status: "prepared",
        result: %{
          "source_digest" => Codec.digest(plan.source),
          "destination_digest" => Codec.digest(plan.destination)
        }
      }

      op = if old, do: Tx.update!(old, Map.delete(attrs, :id)), else: Tx.insert!(Operation, attrs)

      for row <- Enum.sort_by([plan.source_row, dest_row], & &1.zone_id) do
        Tx.insert!(Reservation, %{snapshot_id: row.id, transfer_id: op.id, revision: row.revision})
      end

      {:ok, {:prepared, op}}
    else
      false -> {:error, :stale_transfer}
      error -> error
    end
  end

  defp destination_row(world, %{destination_row: nil} = plan),
    do: Footprints.expand!(world, plan.exp, plan.destination, plan.principal)

  defp destination_row(_world, plan), do: {:ok, plan.destination_row}

  @spec accessible(snapshot :: String.t(), operation :: String.t() | nil) ::
          :ok | {:error, atom()}
  def accessible(snapshot, operation \\ nil) do
    case Repo.get(Reservation, snapshot) do
      nil -> :ok
      %{transfer_id: ^operation} when not is_nil(operation) -> :ok
      _ -> {:error, :transfer_busy}
    end
  end

  @doc "Reads the fence and snapshot under one short lock, so a response cannot straddle transfer commit/installation."
  @spec read(world :: String.t(), snapshot :: String.t(), operation :: String.t() | nil) :: term()
  def read(world, snapshot, operation \\ nil) do
    Tx.run(world, fn _ ->
      with :ok <- accessible(snapshot, operation),
           %Snapshot{world_id: ^world} = row <- Repo.get(Snapshot, snapshot) do
        Snapshots.load(row)
      else
        {:error, _} = error -> error
        _ -> {:error, :unavailable}
      end
    end)
  end

  @spec reserved(snapshot :: String.t(), operation :: String.t()) :: :ok | {:error, atom()}
  def reserved(snapshot, operation) do
    if match?(%{transfer_id: ^operation}, Repo.get(Reservation, snapshot)),
      do: :ok,
      else: {:error, :stale_transfer}
  end

  @spec commit(
          scope :: term(),
          operation :: map(),
          source :: map(),
          destination :: map(),
          opts :: keyword()
        ) :: term()
  def commit(scope, op, source, destination, opts) do
    Tx.run(op.world_id, fn world ->
      with ^op <- Repo.get(Operation, op.id),
           true <- op.status == "prepared" and op.generation == world.generation,
           {:ok, principal, row} <-
             Authority.principal(scope, world.id, op.experience_id, op.actor_id),
           true <- principal.status == :active and row.id == op.source_snapshot_id,
           :ok <- reserved_revision(op.source_snapshot_id, op.id, source.revision),
           :ok <- reserved_revision(op.destination_snapshot_id, op.id, destination.revision),
           {:ok, current_source} <- Snapshots.load(row),
           dest_row = Repo.get!(Snapshot, op.destination_snapshot_id),
           {:ok, current_dest} <- Snapshots.load(dest_row),
           true <- current_source == source and current_dest == destination,
           :ok <- capacity(op.experience_id),
           {:ok, left, right} <- candidate(op, source, destination) do
        events = [
          save_side(world, row, source, left, principal, op, "departed"),
          save_side(world, dest_row, destination, right, principal, op, "arrived")
        ]

        events = events ++ save_exchange(world, dest_row, destination, right, principal, op)

        result = %{
          "id" => op.id,
          "actor_id" => op.actor_id,
          "from" => source.zone_id,
          "to" => destination.zone_id,
          "source_revision" => left.revision,
          "destination_revision" => right.revision,
          "event_ids" => Enum.map(events, & &1.id)
        }

        Tx.update!(op, %{status: "committed", result: result})

        Tx.remember!(
          world.id,
          "travel:" <> row.scope_key,
          principal.user_id,
          op.request_id,
          Codec.load(op.payload) |> elem(1),
          result
        )

        Actions.fault(opts, :transfer_before_commit)
        {:ok, result}
      else
        false -> {:error, :stale_transfer}
        {:error, _} = error -> error
        _ -> {:error, :stale_transfer}
      end
    end)
  end

  @spec candidate(operation :: map(), source :: map(), destination :: map()) :: term()
  def candidate(op, source, destination) do
    with {:ok, {_campaign, actor, token}} <- Codec.load(op.payload),
         true <- actor == op.actor_id and valid_token?(token) do
      Transfer.execute(source, destination, actor, token["exchange"], op.id)
    else
      _ -> {:error, :invalid_transfer}
    end
  end

  defp save_exchange(world, row, before, next, principal, op) do
    for effect <- next.events -- before.events do
      Tx.event!(world, %{
        snapshot_id: row.id,
        scope_key: row.scope_key,
        kind: "experience",
        experience_id: op.experience_id,
        campaign_id: principal.campaign_id,
        principal_id: principal.user_id,
        actor_id: op.actor_id,
        core_event_id: effect.id,
        event: Codec.dump!(effect),
        transition: %{"format" => 1, "unchanged" => Codec.digest(next)},
        audience_users: Authority.audience_users(principal, effect)
      })
    end
  end

  defp reserved_revision(snapshot, operation, revision) do
    if match?(%{transfer_id: ^operation, revision: ^revision}, Repo.get(Reservation, snapshot)),
      do: :ok,
      else: {:error, :stale_transfer}
  end

  defp save_side(world, row, before, next, principal, op, direction) do
    Snapshots.save!(row, next)
    {:ok, transition} = Transition.between(before, next)
    # Freeze occupants and visibility at occurrence. Departure does not reveal
    # the destination, and neither side discloses carried items or knowledge.
    actor = before.actors[op.actor_id] || next.actors[op.actor_id]
    present = Map.keys(Map.merge(before.actors, next.actors))

    audience =
      case actor.audience do
        :public -> {:actors, present}
        :gm -> :gm
        {:actors, ids} -> {:actors, Enum.filter(ids, &(&1 in present))}
      end

    event = %{
      id: op.id <> "/" <> direction,
      scope: next.scope,
      type: "actor_" <> direction,
      actor_id: op.actor_id,
      target_id: next.zone_id,
      occurred_at: next.time.value,
      source_ids: [],
      audience: audience,
      result: %{"actor_id" => op.actor_id, "zone_id" => next.zone_id}
    }

    Tx.event!(world, %{
      snapshot_id: row.id,
      scope_key: row.scope_key,
      kind: "experience",
      experience_id: op.experience_id,
      campaign_id: principal.campaign_id,
      principal_id: principal.user_id,
      actor_id: op.actor_id,
      core_event_id: event.id,
      event: Codec.dump!(event),
      transition: transition,
      audience_users: Authority.audience_users(principal, event)
    })
  end

  @spec finish(operation :: map()) :: term()
  def finish(op) do
    Tx.run(op.world_id, fn world ->
      with %{status: "committed"} = current <- Repo.get(Operation, op.id),
           :ok <- TransferRecovery.verify(world, current) do
        Tx.update!(current, %{status: "installed"})
        Repo.delete_all(from r in Reservation, where: r.transfer_id == ^op.id)
        {:ok, current.result}
      else
        {:error, _} = error -> error
        _ -> {:error, :stale_transfer}
      end
    end)
  end

  @doc "Only after the owning World has stopped affected caches, or during cold World startup."
  @spec recover(world :: String.t(), id :: String.t() | nil) :: term()
  def recover(world, id \\ nil) do
    Tx.run(world, fn record ->
      query =
        from o in Operation, where: o.world_id == ^world and o.status in ["prepared", "committed"]

      query = if id, do: from(o in query, where: o.id == ^id), else: query

      recover_operations(Repo.all(query), record)
    end)
  end

  defp recover_operations(ops, record) do
    Enum.reduce_while(ops, {:ok, :recovered}, fn op, _ ->
      case TransferRecovery.verify(record, op) do
        :ok ->
          Tx.update!(op, %{status: if(op.status == "committed", do: "installed", else: "aborted")})

          Repo.delete_all(from r in Reservation, where: r.transfer_id == ^op.id)
          {:cont, {:ok, :recovered}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp capacity(exp) do
    count =
      Repo.aggregate(
        from(e in Event, where: e.experience_id == ^exp and not is_nil(e.actor_id)),
        :count
      )

    if count <= 197, do: :ok, else: {:error, :capacity_limit}
  end
end
