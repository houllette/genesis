defmodule Genesis.Persistence.LocalTime do
  @moduledoc "Bounded Experience cursor derived from its owned snapshots, not another mutable clock."
  import Ecto.Query
  alias Genesis.Persistence.{Checkpoint, Codec, Event, Footprints, Transfers}
  alias Genesis.Repo

  @spec summary(experience :: map()) :: {:ok, map()} | {:error, atom()}
  def summary(exp) do
    with {:ok, rows} <- Footprints.snapshots(exp),
         true <- Enum.all?(rows, &(Transfers.accessible(&1.id) == :ok)),
         {:ok, pairs} <- Footprints.load(rows),
         true <- Enum.all?(pairs, &coherent?/1) do
      elapsed = pairs |> Enum.map(fn {_, state} -> state.elapsed end) |> Enum.max()

      events =
        Repo.all(
          from e in Event, where: e.experience_id == ^exp.id, order_by: e.cursor, limit: 2049
        )

      cond do
        length(events) > 2048 -> {:error, :capacity_limit}
        not valid_event_times?(events, pairs) -> {:error, :incoherent_local_time}
        true -> {:ok, %{elapsed_seconds: elapsed, zones: length(rows), events: events}}
      end
    else
      false -> {:error, :incoherent_local_time}
      error -> error
    end
  end

  defp valid_event_times?(events, pairs) do
    finish = pairs |> Enum.map(fn {_, state} -> state.time.value end) |> Enum.max()
    start = pairs |> Enum.map(fn {_, state} -> state.time.value - state.elapsed end) |> Enum.min()

    Enum.all?(events, fn event ->
      case Codec.load(event.event) do
        {:ok, %{occurred_at: time}} -> is_integer(time) and time >= start and time <= finish
        {:ok, %{}} -> is_nil(event.actor_id)
        _ -> false
      end
    end)
  end

  @spec admit(experience :: map(), before :: map(), next :: map()) :: :ok | {:error, atom()}
  def admit(_exp, %{elapsed: elapsed, time: time}, %{elapsed: elapsed, time: time}), do: :ok

  def admit(exp, before, next) do
    with true <-
           next.elapsed >= before.elapsed and
             next.time.value - before.time.value == next.elapsed - before.elapsed,
         {:ok, summary} <- summary(exp) do
      cond do
        next.elapsed > 31_622_400 ->
          {:error, :time_capacity_limit}

        next.elapsed > before.elapsed and summary.zones > 1 ->
          {:error, :multi_zone_time_unavailable}

        true ->
          :ok
      end
    else
      false -> {:error, :incoherent_local_time}
      error -> error
    end
  end

  @spec entries(events :: [map()]) :: [map()]
  def entries(events), do: Enum.flat_map(events, &entry/1)

  defp entry(event) do
    case Codec.load(event.event) do
      {:ok, %{time: %{"format" => 1} = time} = effect} ->
        [
          %{
            id: event.id,
            type: effect.type,
            seconds: time["seconds"],
            from: time["from"],
            to: time["to"],
            source_id: event.core_event_id,
            reason: get_in(effect, [:result, "reason"])
          }
        ]

      _ ->
        []
    end
  end

  defp coherent?({row, state}) do
    with %Checkpoint{} = cp <- Repo.get(Checkpoint, row.base_checkpoint_id),
         true <- cp.world_id == row.world_id,
         {:ok, base} <- Codec.load_state(cp.state),
         true <- cp.digest == Codec.digest(base) do
      state.time.value - state.elapsed == base.time.value and base.zone_id == state.zone_id and
        state.time.calendar_id == base.time.calendar_id and
        state.time.calendar_version == base.time.calendar_version
    else
      _ -> false
    end
  end
end
