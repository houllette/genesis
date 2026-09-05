defmodule Genesis.Persistence.GlobalPublication do
  @moduledoc "Seal, replay and atomic incorporation of World-owned scoped standing dependencies."
  import Ecto.Query
  alias Genesis.Persistence.Codec
  alias Genesis.Persistence.Event
  alias Genesis.Persistence.GlobalDependency
  alias Genesis.Persistence.Standing
  alias Genesis.Persistence.Tx
  alias Genesis.Repo
  alias Genesis.Worlds
  alias Genesis.WorldStandings

  @spec rows(experience :: String.t()) :: [map()]
  def rows(exp),
    do:
      Repo.all(
        from r in Standing, where: r.experience_id == ^exp, order_by: r.resource_id, limit: 201
      )

  @spec seal(experience :: String.t()) :: map()
  def seal(exp) do
    dependencies =
      Repo.all(
        from d in GlobalDependency, where: d.experience_id == ^exp, order_by: d.resource_id
      )

    %{
      "rows" =>
        Enum.map(
          rows(exp),
          &%{
            "id" => &1.id,
            "world_id" => &1.world_id,
            "generation" => &1.generation,
            "experience_id" => &1.experience_id,
            "scope_key" => &1.scope_key,
            "resource_id" => &1.resource_id,
            "institution_id" => &1.institution_id,
            "actor_id" => &1.actor_id,
            "digest" => &1.digest,
            "base_digest" => Codec.digest(&1.base),
            "revision" => &1.revision
          }
        ),
      "dependencies" =>
        Enum.map(
          dependencies,
          &Map.take(&1, [:resource_id, :base_digest, :network_revision, :mode])
        )
        |> Enum.map(fn d -> Map.new(d, fn {k, v} -> {Atom.to_string(k), v} end) end)
    }
  end

  @spec prepare(world :: map(), exp :: map(), mapping :: map()) :: term()
  def prepare(world, exp, mapping) do
    records = rows(exp.id)
    dependencies = Repo.all(from d in GlobalDependency, where: d.experience_id == ^exp.id)

    if length(records) <= 200 and
         Enum.sort(Enum.map(records, & &1.resource_id)) ==
           Enum.sort(Enum.map(dependencies, & &1.resource_id)) do
      prepare_rows(records, world, dependencies, mapping)
    else
      {:error, :stale_global_dependencies}
    end
  end

  defp prepare_rows(records, world, dependencies, mapping) do
    Enum.reduce_while(records, {:ok, []}, fn row, {:ok, plans} ->
      case prepare_row(world, row, dependencies, mapping) do
        {:ok, plan} -> {:cont, {:ok, plans ++ [plan]}}
        error -> {:halt, error}
      end
    end)
  end

  defp prepare_row(world, row, dependencies, mapping) do
    dependency = Enum.find(dependencies, &(&1.resource_id == row.resource_id))

    network =
      Repo.get_by(Genesis.Persistence.Network, world_id: world.id, generation: world.generation)

    with {:ok, _, _} <- WorldStandings.validate_row(row),
         true <- row.world_id == world.id and row.generation == world.generation,
         {:ok, base} <- WorldStandings.published(world.id, world.generation, row.resource_id),
         true <- base == row.base and dependency.base_digest == Codec.digest(base),
         true <-
           dependency.generation == world.generation and dependency.world_id == world.id and
             dependency.mode == "write",
         true <- not is_nil(network) and dependency.network_revision == network.revision,
         {:ok, events} <- replay(row) do
      candidate =
        Map.update!(row.data, "sources", &Enum.map(&1, fn id -> Map.get(mapping, id, id) end))

      {:ok,
       %{
         row: row,
         candidate: candidate,
         events: events,
         manifest: %{
           "resource_id" => row.resource_id,
           "base_digest" => Codec.digest(base),
           "candidate_digest" => Codec.digest(candidate),
           "working_digest" => row.digest
         }
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :stale_global_dependencies}
    end
  end

  @spec replay(row :: map()) :: term()
  def replay(row) do
    key = "standing:" <> row.experience_id <> ":" <> row.resource_id

    events =
      Repo.all(
        from e in Event,
          where: e.world_id == ^row.world_id and e.scope_key == ^key,
          order_by: e.cursor,
          limit: 201
      )

    result =
      Enum.reduce_while(events, {:ok, row.base}, fn e, {:ok, before} ->
        with {:ok, effect} <- Codec.load(e.event),
             true <- e.kind == "experience" and e.experience_id == row.experience_id,
             true <- effect_identity?(effect, row),
             true <- effect["before_digest"] == Codec.digest(before),
             next = effect["after_data"],
             true <- Genesis.Core.Standing.valid?(next) do
          {:cont, {:ok, next}}
        else
          _ -> {:halt, {:error, :corrupt_global_history}}
        end
      end)

    if length(events) == row.revision and result == {:ok, row.data},
      do: {:ok, events},
      else: {:error, :corrupt_global_history}
  end

  @spec publish!(world :: map(), plans :: list(), mapping :: map(), user :: String.t()) :: [map()]
  def publish!(world, plans, mapping, user) do
    Enum.flat_map(plans, fn plan ->
      row = plan.row

      original =
        Repo.get_by(Standing,
          world_id: world.id,
          generation: world.generation,
          scope_key: "published",
          resource_id: row.resource_id
        )

      attrs = %{
        world_id: world.id,
        generation: world.generation,
        scope_key: "published",
        experience_id: nil,
        resource_id: row.resource_id,
        institution_id: row.institution_id,
        actor_id: row.actor_id,
        base: if(original, do: original.base, else: row.base),
        data: plan.candidate,
        digest: Codec.digest(plan.candidate),
        revision: if(original, do: original.revision + 1, else: 1)
      }

      if original, do: Tx.update!(original, attrs), else: Tx.insert!(Standing, attrs)

      {events, _after_data} =
        Enum.map_reduce(plan.events, row.base, fn source, before ->
          {:ok, effect} = Codec.load(source.event)
          id = Worlds.named_id(["incorporation", row.experience_id, source.id])

          effect =
            effect
            |> Map.put(:id, id)
            |> Map.put(:source_ids, Enum.map(effect.source_ids, &Map.get(mapping, &1, &1)))
            |> Map.put("before_digest", Codec.digest(before))
            |> Map.update!("after_data", &mapped_data(&1, mapping))

          published =
            Tx.event!(world, %{
              scope_key: "standing:published:" <> row.resource_id,
              kind: "world",
              principal_id: user,
              core_event_id: id,
              source_event_id: source.id,
              campaign_id: source.campaign_id,
              audience_users: source.audience_users,
              event: Codec.dump!(effect)
            })

          {published, effect["after_data"]}
        end)

      Repo.delete_all(
        from d in GlobalDependency,
          where: d.experience_id == ^row.experience_id and d.resource_id == ^row.resource_id
      )

      events
    end)
  end

  defp mapped_data(data, mapping),
    do:
      Map.update!(
        data,
        "sources",
        &Enum.map(&1, fn source -> Map.get(mapping, source, source) end)
      )

  @doc "Reconstructs a published standing from recorded transitions, without re-running contributions. Internal authorized callers hold the World fence."
  @spec replay_published(row :: map()) :: term()
  def replay_published(row) do
    key = "standing:published:" <> row.resource_id

    events =
      Repo.all(
        from e in Event,
          where: e.world_id == ^row.world_id and e.scope_key == ^key,
          order_by: e.cursor,
          limit: 201
      )

    result =
      Enum.reduce_while(events, {:ok, row.base}, fn event, {:ok, before} ->
        with {:ok, effect} <- Codec.load(event.event),
             true <- event.kind == "world" and not is_nil(event.source_event_id),
             true <- effect_identity?(effect, row),
             true <- effect["before_digest"] == Codec.digest(before),
             true <- Genesis.Core.Standing.valid?(effect["after_data"]) do
          {:cont, {:ok, effect["after_data"]}}
        else
          _ -> {:halt, {:error, :corrupt_global_history}}
        end
      end)

    if length(events) <= 200 and result == {:ok, row.data},
      do: result,
      else: {:error, :corrupt_global_history}
  end

  defp effect_identity?(
         %{type: "standing_reported", actor_id: actor, target_id: target, result: result},
         row
       ),
       do:
         actor == row.actor_id and target == row.institution_id and
           result["resource_id"] == row.resource_id

  defp effect_identity?(_effect, _row), do: false

  @spec matches?(operation :: map(), field :: String.t()) :: boolean()
  def matches?(op, field) do
    Enum.all?(Map.get(op.manifest, "global", []), fn entry ->
      case WorldStandings.published(op.world_id, op.generation, entry["resource_id"]) do
        {:ok, data} -> Codec.digest(data) == entry[field]
        _ -> false
      end
    end)
  end

  @spec released?(experience :: String.t()) :: boolean()
  def released?(exp),
    do: not Repo.exists?(from d in GlobalDependency, where: d.experience_id == ^exp)
end
