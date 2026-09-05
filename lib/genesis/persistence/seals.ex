defmodule Genesis.Persistence.Seals do
  @moduledoc "Immutable completion manifests bind every working snapshot, base, claim and recorded event."
  import Ecto.Query
  alias Genesis.Core.LocalTime
  alias Genesis.Persistence.Claim
  alias Genesis.Persistence.Codec
  alias Genesis.Persistence.Event
  alias Genesis.Persistence.Footprints
  alias Genesis.Persistence.GlobalPublication
  alias Genesis.Persistence.World
  alias Genesis.Repo

  @spec basis(experience :: map()) :: {:ok, String.t()} | {:error, atom()}
  def basis(exp) do
    with {:ok, manifest} <- capture(exp), do: {:ok, Codec.digest(manifest)}
  end

  @spec capture(experience :: map()) :: {:ok, map()} | {:error, atom()}
  def capture(exp) do
    with {:ok, rows} <- Footprints.snapshots(exp),
         {:ok, states} <- Footprints.load(rows),
         events =
           Repo.all(
             from e in Event,
               where: e.experience_id == ^exp.id,
               order_by: e.cursor,
               limit: 2049
           ),
         true <- length(events) <= 2048 do
      claims =
        Repo.all(
          from c in Claim,
            where: c.experience_id == ^exp.id,
            order_by: [c.resource_kind, c.resource_id],
            select: [c.resource_kind, c.resource_id]
        )

      manifest = %{
        "format" => 2,
        "experience_id" => exp.id,
        "window_id" => exp.window_id,
        "elapsed_seconds" => states |> Enum.map(fn {_, s} -> s.elapsed end) |> Enum.max(),
        "zones" =>
          Enum.map(
            rows,
            &%{
              "snapshot_id" => &1.id,
              "zone_id" => &1.zone_id,
              "digest" => &1.digest,
              "base_checkpoint_id" => &1.base_checkpoint_id
            }
          ),
        "claims" => claims,
        "events" => Enum.map(events, &event_manifest/1)
      }

      global = GlobalPublication.seal(exp.id)

      manifest =
        if global["rows"] == [] and global["dependencies"] == [],
          do: manifest,
          else: Map.put(manifest, "global", global)

      calendar = Repo.get!(World, exp.world_id).calendar
      manifest = if calendar == %{}, do: manifest, else: Map.put(manifest, "calendar", calendar)

      {:ok, manifest}
    else
      false -> {:error, :capacity_limit}
      error -> error
    end
  end

  @spec validate(experience :: map()) :: :ok | {:error, atom()}
  def validate(
        %{completion: %{"format" => 3, "declaration" => declaration, "completion_id" => id}} = exp
      ) do
    with true <-
           exp.status ==
             if(declaration["review_required"] == true, do: "needs_review", else: "ready"),
         %Event{} = event <- Repo.get_by(Event, experience_id: exp.id, core_event_id: id),
         {:ok, %{result: %{"declaration" => ^declaration}}} <- Codec.load(event.event),
         {:ok, current} <- capture_completion(exp, declaration, id),
         true <- current == exp.completion do
      :ok
    else
      _ -> {:error, :sealed_footprint_changed}
    end
  end

  def validate(%{completion: %{"format" => 2}} = exp) do
    with {:ok, current} <- capture(exp), true <- current == exp.completion do
      :ok
    else
      _ -> {:error, :sealed_footprint_changed}
    end
  end

  def validate(%{completion: %{"format" => 1, "snapshot_digest" => digest}} = exp) do
    case Footprints.snapshots(exp) do
      {:ok, [%{digest: ^digest}]} -> :ok
      _ -> {:error, :sealed_footprint_changed}
    end
  end

  def validate(_exp), do: {:error, :unsealed_experience}

  @spec capture_completion(experience :: map(), declaration :: map(), completion_id :: String.t()) ::
          {:ok, map()} | {:error, atom()}
  def capture_completion(exp, declaration, id) do
    with {:ok, manifest} <- capture(exp),
         {:ok, declaration} <-
           LocalTime.declaration(declaration, manifest["elapsed_seconds"]) do
      {:ok,
       Map.merge(manifest, %{
         "format" => 3,
         "completion_id" => id,
         "recorded_elapsed_seconds" => manifest["elapsed_seconds"],
         "elapsed_seconds" => declaration["elapsed_seconds"],
         "declaration" => declaration
       })}
    end
  end

  defp event_manifest(event) do
    fields = [
      :world_id,
      :scope_key,
      :snapshot_id,
      :experience_id,
      :campaign_id,
      :kind,
      :principal_id,
      :actor_id,
      :core_event_id,
      :source_event_id,
      :cursor,
      :recorded_at,
      :audience_users,
      :event
    ]

    content = Map.new(fields, &{Atom.to_string(&1), Map.fetch!(event, &1)})
    %{"id" => event.id, "digest" => Codec.digest(content)}
  end
end
