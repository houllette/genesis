defmodule Genesis.Engine.Supervisor do
  @moduledoc "Single-node process lookup and dynamic world trees. No world starts without explicit admission."
  use Supervisor
  alias Genesis.Core.Scope
  alias Genesis.Engine.World

  @spec start_link(opts :: keyword()) :: Supervisor.on_start()
  def start_link(opts),
    do: Supervisor.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  @impl true
  def init(opts) do
    Supervisor.init(
      [
        {Registry, keys: :unique, name: Keyword.fetch!(opts, :registry)},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Keyword.fetch!(opts, :worlds), max_children: 32}
      ],
      strategy: :rest_for_one
    )
  end

  @spec start_world(registry :: atom(), supervisor :: atom(), opts :: keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_world(registry, supervisor, opts) do
    with {:ok, _scope} <-
           Scope.new(%{
             world_id: Keyword.get(opts, :world_id),
             generation: Keyword.get(opts, :generation),
             kind: :published
           }) do
      start_valid_world(
        registry,
        supervisor,
        Keyword.merge(opts, registry: registry, owner: self())
      )
    end
  end

  defp start_valid_world(registry, supervisor, opts) do
    case DynamicSupervisor.start_child(supervisor, {Genesis.Engine.WorldSupervisor, opts}) do
      {:ok, _supervisor} ->
        existing_world(registry, opts)

      {:error, {:already_started, _supervisor}} ->
        existing_world(registry, opts)

      error ->
        error
    end
  end

  @spec via(registry :: atom(), key :: term()) :: {:via, Registry, {atom(), term()}}
  def via(registry, key), do: {:via, Registry, {registry, key}}

  defp world_name(registry, opts),
    do: via(registry, {:world, Keyword.fetch!(opts, :world_id)})

  defp existing_world(registry, opts) do
    world = GenServer.whereis(world_name(registry, opts))

    if World.identity(world) ==
         {Keyword.fetch!(opts, :world_id), Keyword.fetch!(opts, :generation)},
       do: {:ok, world},
       else: {:error, :generation_mismatch}
  end
end
