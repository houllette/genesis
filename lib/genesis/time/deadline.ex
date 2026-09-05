defmodule Genesis.Time.Deadline do
  @moduledoc "Restart-safe real deadlines. Saved remaining time caps backward wall jumps; fiction is untouched."
  alias Genesis.Time.Clock
  @spec recover(saved :: map(), clock :: Clock.t()) :: {:ok, map()} | {:error, atom()}
  def recover(saved, clock \\ Clock.system())
  def recover(%{} = empty, _clock) when map_size(empty) == 0, do: {:ok, %{}}

  def recover(
        %{"format" => 1, "remaining_ms" => remaining, "paused" => paused, "deadline_at" => iso} =
          saved,
        clock
      )
      when is_integer(remaining) and remaining in 0..86_400_000 and is_boolean(paused) and
             is_binary(iso) and map_size(saved) == 4 do
    case DateTime.from_iso8601(iso) do
      {:ok, deadline, 0} ->
        now = Clock.read(clock)

        left =
          if paused,
            do: remaining,
            else: min(remaining, max(0, DateTime.diff(deadline, now.utc, :millisecond)))

        {:ok, %{remaining_ms: left, monotonic_deadline_ms: now.monotonic_ms + left}}

      _ ->
        {:error, :invalid_deadline}
    end
  end

  def recover(_saved, _clock), do: {:error, :invalid_deadline}

  @spec change(saved :: map(), action :: :pause | :resume | :ready, clock :: Clock.t()) ::
          {:ok, map()} | {:error, atom()}
  def change(saved, action, clock) do
    with {:ok, recovered} <- recover(saved, clock) do
      if recovered == %{} do
        {:ok, %{}}
      else
        now = Clock.read(clock)

        {:ok,
         %{
           "format" => 1,
           "remaining_ms" => recovered.remaining_ms,
           "paused" => action != :resume,
           "deadline_at" =>
             now.utc
             |> DateTime.add(recovered.remaining_ms, :millisecond)
             |> DateTime.to_iso8601()
         }}
      end
    end
  end
end
