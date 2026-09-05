defmodule Genesis.Engine.CommandCoordinator do
  @moduledoc "Delegates owner commands without blocking World's authorization mailbox."
  use GenServer, restart: :temporary
  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  @impl true
  def init(opts), do: {:ok, Map.new(opts), {:continue, :command}}
  @impl true
  def handle_continue(:command, state) do
    result = GenServer.call(state.zone, state.command, 10_000)
    send(state.world, {:command_done, self(), result})
    {:stop, :normal, state}
  end
end
