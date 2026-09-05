defmodule Genesis.Engine.TransferCoordinator do
  @moduledoc "Short-lived coordinator. Zones validate independently; no transaction spans process calls."
  use GenServer, restart: :temporary
  alias Genesis.Persistence.{Actions, Transfers}

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts), do: {:ok, Map.new(opts), {:continue, :move}}

  @impl true
  def handle_continue(:move, state) do
    result = move(state)
    send(state.world, {:transfer_done, self(), result})
    {:stop, :normal, state}
  end

  defp move(state) do
    %{operation: op, source: source, destination: destination} = state
    Actions.fault(state.opts, :transfer_after_prepare)

    with {:ok, scenes} <- reserve(state),
         {:ok, left, right} <- Transfers.candidate(op, scenes[source], scenes[destination]),
         :ok <- GenServer.call(source, {:validate_transfer, op.id, left}),
         :ok <- GenServer.call(destination, {:validate_transfer, op.id, right}),
         {:ok, result} <-
           Transfers.commit(state.scope, op, scenes[source], scenes[destination], state.opts) do
      Actions.fault(state.opts, :transfer_after_commit)
      :ok = GenServer.call(source, {:install_transfer, op.id})
      Actions.fault(state.opts, :transfer_after_first_install)
      :ok = GenServer.call(destination, {:install_transfer, op.id})
      {:ok, ^result} = Transfers.finish(op)
      {:ok, result}
    end
  end

  defp reserve(state) do
    # Stable order is explicit even though durable reservations already fence
    # both writers atomically. Never call one Zone from the other Zone.
    [
      {state.operation.source_snapshot_id, state.source},
      {state.operation.destination_snapshot_id, state.destination}
    ]
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, %{}}, fn {_id, zone}, {:ok, scenes} ->
      case GenServer.call(zone, {:reserve_transfer, state.operation.id}) do
        {:ok, scene} -> {:cont, {:ok, Map.put(scenes, zone, scene)}}
        error -> {:halt, error}
      end
    end)
  end
end
