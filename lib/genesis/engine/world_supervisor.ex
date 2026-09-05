defmodule Genesis.Engine.WorldSupervisor do
  @moduledoc "World failure tears down its ephemeral zones and attachments before claims can be reissued."
  use Supervisor
  alias Genesis.Engine.Supervisor, as: Lookup

  @spec start_link(opts :: keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    key = Keyword.fetch!(opts, :world_id)

    Supervisor.start_link(__MODULE__, opts,
      name: Lookup.via(Keyword.fetch!(opts, :registry), {:world_tree, key})
    )
  end

  @impl true
  def init(opts) do
    key = Keyword.fetch!(opts, :world_id)
    workers = Lookup.via(Keyword.fetch!(opts, :registry), {:workers, key})

    Supervisor.init(
      [
        {Genesis.Engine.World, Keyword.put(opts, :workers, workers)},
        {DynamicSupervisor, strategy: :one_for_one, name: workers, max_children: 80}
      ],
      strategy: :rest_for_one
    )
  end
end
