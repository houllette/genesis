defmodule Genesis.Engine.Runtime do
  @moduledoc "Authenticated entry to the durable World authority. No client-controlled state or grant fields."
  alias Genesis.Engine.{Supervisor, World}
  alias Genesis.Persistence.Access
  alias Genesis.Worlds

  @spec call(scope :: term(), world_id :: String.t(), command :: term()) :: term()
  def call(scope, world_id, command) do
    with :ok <- Access.world(scope, world_id),
         {:ok, world} <- Worlds.get_world(scope, world_id),
         {:ok, pid} <-
           Supervisor.start_world(Genesis.Engine.Registry, Genesis.Engine.Worlds,
             world_id: world.id,
             generation: world.generation,
             storage: :postgres
           ),
         :postgres <- World.mode(pid) do
      GenServer.call(pid, {:durable, scope, command}, 15_000)
    else
      {:error, _reason} = error -> error
      _ -> {:error, :authority_mode_mismatch}
    end
  end

  @spec attach(
          scope :: term(),
          world_id :: String.t(),
          experience_id :: String.t(),
          actor_id :: String.t() | nil
        ) :: {:ok, pid()} | {:error, term()}
  def attach(scope, world, experience, actor),
    do: call(scope, world, {:open, experience, actor, self()})
end
