defmodule Genesis.Persistence.Transition do
  @moduledoc "Recorded field transitions, never historical intents or rerolls."
  alias Genesis.Core.State
  alias Genesis.Persistence.Codec
  @spec between(before :: map(), after_state :: map()) :: {:ok, map()} | {:error, atom()}
  def between(%State{} = before, %State{} = after_state) do
    if before.scope == after_state.scope and before.zone_id == after_state.zone_id and
         after_state.revision == before.revision + 1 do
      changes =
        for {field, value} <- Map.from_struct(after_state),
            Map.fetch!(before, field) != value,
            into: %{},
            do: {field, value}

      {:ok,
       %{
         "format" => 1,
         "before" => Codec.digest(before),
         "after" => Codec.digest(after_state),
         "changes" => Codec.dump!(changes)
       }}
    else
      {:error, :invalid_transition}
    end
  end

  @spec apply(state :: map(), transition :: map()) :: {:ok, map()} | {:error, atom()}
  def apply(state, %{"format" => 1, "unchanged" => digest}),
    do: if(Codec.digest(state) == digest, do: {:ok, state}, else: {:error, :replay_conflict})

  def apply(state, %{
        "format" => 1,
        "before" => before,
        "after" => after_hash,
        "changes" => encoded
      }) do
    with true <- Codec.digest(state) == before,
         {:ok, changes} when is_map(changes) <- Codec.load(encoded),
         true <- Enum.all?(Map.keys(changes), &Map.has_key?(Map.from_struct(state), &1)),
         next = struct(state, changes),
         true <- next.scope == state.scope and next.zone_id == state.zone_id,
         true <- next.revision == state.revision + 1 and Codec.digest(next) == after_hash,
         {:ok, _state} <- State.restore(next) do
      {:ok, next}
    else
      _ -> {:error, :replay_conflict}
    end
  end

  def apply(_state, _transition), do: {:error, :unsupported_transition}
end
