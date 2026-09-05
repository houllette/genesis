defmodule Genesis.Engine.PublicationCoordinator do
  @moduledoc "World-delegated publication: independent Zone validation, short SQL commit, cache installation, release."
  use GenServer, restart: :temporary
  alias Genesis.Persistence.{Actions, Incorporation}
  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  @impl true
  def init(opts), do: {:ok, Map.new(opts), {:continue, :publish}}
  @impl true
  def handle_continue(:publish, state) do
    result = publish(state)
    send(state.world, {:publication_done, self(), result})
    {:stop, :normal, state}
  end

  defp publish(state) do
    Actions.fault(state.opts, :publication_after_prepare)

    with :ok <- validate(state),
         {:ok, result} <- Incorporation.publish(state.scope, state.operation, state.opts) do
      Actions.fault(state.opts, :after_commit)

      install(state)

      Actions.fault(state.opts, :after_install)
      {:ok, ^result} = Incorporation.finish(state.operation)
      {:ok, result}
    end
  end

  defp install(state) do
    Enum.with_index(state.zones)
    |> Enum.each(fn {{pid, _candidate}, index} ->
      :ok = GenServer.call(pid, {:install_publication, state.operation.id})
      if index == 0, do: Actions.fault(state.opts, :publication_after_first_install)
    end)
  end

  defp validate(state) do
    Enum.reduce_while(state.zones, :ok, fn {pid, candidate}, :ok ->
      case GenServer.call(pid, {:validate_publication, state.operation.id, candidate}) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
