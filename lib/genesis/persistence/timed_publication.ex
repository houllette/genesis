defmodule Genesis.Persistence.TimedPublication do
  @moduledoc "Atomic timed publication, source links and explicit reward quarantine, under the existing cache fence."
  import Ecto.Query

  alias Genesis.Persistence.{
    Claim,
    Codec,
    Event,
    Experience,
    GlobalDependency,
    GlobalPublication,
    Preparation,
    Snapshot,
    Snapshots,
    Transition,
    Tx,
    Window,
    World
  }

  alias Genesis.Repo

  @spec commit(world :: map(), user :: String.t(), prepared :: map(), request :: String.t()) ::
          map()
  def commit(world, user, prepared, request) do
    Snapshots.reindex!(
      Enum.map(prepared.zones, & &1.published),
      Enum.map(prepared.zones, & &1.candidate)
    )

    rows = Enum.map(prepared.zones, &Snapshots.save!(&1.published_snapshot, &1.candidate))

    events =
      events(world, user, prepared) ++
        GlobalPublication.publish!(world, prepared.global, prepared.mapping, user)

    statuses = Enum.map(prepared.entries, &close!(world, user, &1))
    Tx.update!(Repo.get!(Window, prepared.preparation.window_id), %{status: "closed"})
    Tx.update!(prepared.preparation, %{status: "published"})
    target = prepared.manifest["target"]

    Tx.update!(Repo.get!(World, world.id), %{revision: world.revision + 1, fictional_time: target})

    Enum.each(rows, &Snapshots.checkpoint!(&1, List.last(events).cursor))

    result = %{
      "snapshot_ids" => Enum.map(rows, & &1.id),
      "zone_ids" => Enum.map(rows, & &1.zone_id),
      "preparation_id" => prepared.preparation.id,
      "status" => "incorporated",
      "experiences" => statuses,
      "event_ids" => Enum.map(events, & &1.id),
      "world_time" => target
    }

    Tx.remember!(world.id, "incorporation", user, request, %{"preview_id" => prepared.id}, result)
    result
  end

  defp close!(world, user, entry) do
    exp = entry.experience

    status =
      if entry.decision["mode"] == "include",
        do: "incorporated",
        else: "closed_without_publication"

    Tx.update!(exp, %{status: status, revision: exp.revision + 1})

    audience =
      Repo.all(from e in Event, where: e.experience_id == ^exp.id, select: e.audience_users)
      |> List.flatten()
      |> Enum.uniq()

    Tx.event!(world, %{
      scope_key: "experience-review:" <> exp.id,
      kind: "experience",
      experience_id: exp.id,
      campaign_id: exp.campaign_id,
      principal_id: user,
      audience_users: Enum.uniq([user | audience]),
      event:
        Codec.dump!(%{
          type: "window_decision",
          source_ids: List.wrap(exp.completion["completion_id"]),
          result: %{
            "status" => status,
            "reason" => entry.decision["reason"],
            "original_elapsed_seconds" => exp.completion["elapsed_seconds"],
            "reviewed_elapsed_seconds" => entry.decision["elapsed_seconds"]
          }
        })
    })

    Repo.delete_all(
      from c in Claim,
        where:
          c.world_id == ^world.id and c.generation == ^world.generation and
            c.experience_id == ^exp.id
    )

    Repo.delete_all(
      from d in GlobalDependency,
        where:
          d.world_id == ^world.id and d.generation == ^world.generation and
            d.experience_id == ^exp.id
    )

    %{"id" => exp.id, "status" => status}
  end

  defp events(world, user, prepared) do
    by_zone = Map.new(prepared.zones, &{&1.published.zone_id, &1})
    source_ids = MapSet.new(prepared.sources, & &1.core_event_id)
    resolved = Map.new(prepared.generated, &{&1["event"].id, &1["event"]})

    sources =
      Enum.map(prepared.sources, fn source ->
        row = Repo.get!(Snapshot, source.snapshot_id)
        {:ok, effect} = Codec.load(source.event)
        effect = Map.get(resolved, source.core_event_id, effect)

        %{
          zone: row.zone_id,
          effect: effect,
          id: prepared.mapping[source.core_event_id],
          source: source
        }
      end)

    generated =
      for entry <- prepared.generated,
          not MapSet.member?(source_ids, entry["event"].id),
          do: %{zone: entry["zone"], effect: entry["event"], id: entry["event"].id, source: nil}

    ordered =
      Enum.sort_by(
        sources ++ generated,
        &{Map.get(&1.effect, :occurred_at, prepared.manifest["target"]),
         if(&1.source, do: &1.source.cursor, else: 0), &1.id}
      )

    {events, seen} =
      Enum.map_reduce(ordered, MapSet.new(), fn entry, seen ->
        zone = by_zone[entry.zone]
        event = mapped(entry, zone, prepared.mapping)

        transition =
          if MapSet.member?(seen, entry.zone),
            do: %{"format" => 1, "unchanged" => Codec.digest(zone.candidate)},
            else: delta(zone)

        attrs = %{
          snapshot_id: zone.published_snapshot.id,
          scope_key: zone.published_snapshot.scope_key,
          kind: "world",
          principal_id: user,
          core_event_id: entry.id,
          actor_id: Map.get(event, :actor_id),
          source_event_id: if(entry.source, do: entry.source.id),
          campaign_id: if(entry.source, do: entry.source.campaign_id),
          audience_users: if(entry.source, do: entry.source.audience_users, else: [user]),
          event: Codec.dump!(event),
          transition: transition
        }

        {Tx.event!(world, attrs), MapSet.put(seen, entry.zone)}
      end)

    empty =
      for zone <- prepared.zones, not MapSet.member?(seen, zone.published.zone_id) do
        Tx.event!(world, %{
          snapshot_id: zone.published_snapshot.id,
          scope_key: zone.published_snapshot.scope_key,
          kind: "world",
          principal_id: user,
          audience_users: [user],
          transition: delta(zone),
          event:
            Codec.dump!(%{
              type: "time_incorporated",
              occurred_at: prepared.manifest["target"],
              result: %{"preparation_id" => prepared.preparation.id}
            })
        })
      end

    events ++ empty
  end

  defp mapped(entry, zone, mapping),
    do:
      entry.effect
      |> Map.put(:id, entry.id)
      |> Map.put(:scope, zone.candidate.scope)
      |> Map.put(:revision, zone.candidate.revision)
      |> Map.update(:source_ids, [], &Enum.map(&1, fn id -> Map.get(mapping, id, id) end))

  defp delta(zone) do
    {:ok, delta} = Transition.between(zone.published, zone.candidate)
    delta
  end

  @spec lifecycle_committed?(operation :: map()) :: boolean()
  def lifecycle_committed?(op) do
    match?(%{status: "closed"}, Repo.get(Window, op.manifest["window_id"])) and
      match?(%{status: "published"}, Repo.get(Preparation, op.manifest["preparation_id"])) and
      Enum.all?(op.manifest["experiences"], fn entry ->
        status =
          if entry["decision"]["mode"] == "include",
            do: "incorporated",
            else: "closed_without_publication"

        match?(%{status: ^status}, Repo.get(Experience, entry["id"])) and
          not Repo.exists?(from c in Claim, where: c.experience_id == ^entry["id"]) and
          GlobalPublication.released?(entry["id"])
      end)
  end
end
