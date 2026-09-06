defmodule Genesis.Persistence.ActionTime do
  @moduledoc "Resolve due points inside a paid action using its captured proposal and draws, without a second duration charge."
  alias Genesis.Core.{DueWork, Scene}
  alias Genesis.Persistence.LocalAdvance

  @spec prepare(
          world :: map(),
          exp :: map(),
          before :: map(),
          next :: map(),
          receipt :: map(),
          opts :: keyword()
        ) :: term()
  def prepare(world, exp, before, next, receipt, opts) do
    if is_nil(DueWork.next(before, next.time.value)) do
      {:ok, before, next, receipt, []}
    else
      with {:ok, current, _target, steps} <-
             LocalAdvance.prepare(world, exp, before, next.time.value),
           {:ok, proposal} <- Keyword.fetch(opts, :proposal),
           {:ok, inputs} <- Keyword.fetch(opts, :inputs),
           semantic = %{
             current
             | time: before.time,
               elapsed: before.elapsed,
               revision: before.revision,
               events: before.events
           },
           {:ok, resolved, effects} <- Scene.confirm(semantic, proposal, inputs),
           true <- resolved.time == next.time and resolved.elapsed == next.elapsed do
        revision = current.revision + 1
        effects = Enum.map(effects, &Map.put(&1, :revision, revision))
        resolved = %{resolved | revision: revision, events: current.events ++ effects}
        {:ok, current, resolved, %{receipt | revision: revision, effects: effects}, steps}
      else
        :error -> {:error, :due_work_pending}
        false -> {:error, :action_time_changed}
        error -> error
      end
    end
  end
end
