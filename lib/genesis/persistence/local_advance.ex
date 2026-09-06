defmodule Genesis.Persistence.LocalAdvance do
  @moduledoc "Scheduled local effects are committed by the owning Zone, with their individual transitions."
  alias Genesis.Core.{DueWork, LocalTime, TimeSteps}
  alias Genesis.Persistence.{Codec, Footprints, Snapshots, Transition, Tx}

  @spec prepare(world :: map(), exp :: map(), state :: map(), target :: integer()) :: term()
  def prepare(world, exp, state, target) do
    with {:ok, context} <- context(world, exp),
         do: TimeSteps.prepare(state, target, world.calendar, context)
  end

  @spec context(world :: map(), exp :: map()) :: term()
  def context(world, exp) do
    with {:ok, published} <- Footprints.load(Snapshots.published(world)),
         {:ok, rows} <- Footprints.snapshots(exp),
         {:ok, working} <- Footprints.load(rows) do
      {:ok,
       Map.new(published ++ working, fn {_, state} ->
         {state.zone_id, DueWork.context_value(state)}
       end)}
    end
  end

  @spec save!(
          world :: map(),
          exp :: map(),
          snapshot :: map(),
          steps :: [map()],
          user :: String.t(),
          clock :: term(),
          audience :: [String.t()] | nil
        ) :: :ok
  def save!(world, exp, snapshot, steps, user, clock, audience \\ nil) do
    Enum.each(steps, fn step ->
      {:ok, transition} = Transition.between(step.before, step.next)
      Snapshots.save!(snapshot, step.next)

      Tx.event!(
        world,
        %{
          snapshot_id: snapshot.id,
          scope_key: snapshot.scope_key,
          kind: "experience",
          experience_id: exp.id,
          campaign_id: exp.campaign_id,
          principal_id: user,
          core_event_id: step.event.id,
          actor_id: step.event.actor_id,
          audience_users: audience || [user],
          event:
            Codec.dump!(
              Map.put(
                step.event,
                :time,
                LocalTime.contribution(step.before, step.next)
              )
            ),
          transition: transition
        },
        clock
      )
    end)

    :ok
  end
end
