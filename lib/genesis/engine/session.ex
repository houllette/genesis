defmodule Genesis.Engine.Session do
  @moduledoc "Transport-neutral attachment. Holds delivery identity, never an authoritative game copy."
  use GenServer, restart: :temporary
  alias Genesis.Engine.Zone

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  @spec view(session :: pid()) :: {:ok, map()} | {:error, atom()}
  def view(session), do: GenServer.call(session, :view, 5000)
  @spec submit(session :: pid(), request :: map()) :: {:ok, map()} | {:error, atom()}
  def submit(session, request), do: GenServer.call(session, {:submit, request}, 5000)

  @spec propose(session :: pid(), id :: String.t(), intent :: map()) ::
          {:ok, map()} | {:error, atom()} | {:clarify, atom()}
  def propose(session, id, intent), do: GenServer.call(session, {:propose, id, intent}, 5000)

  @spec confirm(session :: pid(), request_id :: String.t(), proposal_id :: String.t()) ::
          {:ok, map()} | {:error, atom()}
  def confirm(session, request_id, proposal_id),
    do: GenServer.call(session, {:confirm, request_id, proposal_id}, 5000)

  @spec cancel(session :: pid(), proposal_id :: String.t()) :: :ok | {:error, atom()}
  def cancel(session, proposal_id), do: GenServer.call(session, {:cancel, proposal_id}, 5000)

  @spec submit_step(
          session :: pid(),
          plan_id :: String.t(),
          index :: non_neg_integer(),
          request :: map()
        ) :: term()
  def submit_step(session, plan, index, %{revision: revision, intent: intent} = request)
      when map_size(request) == 2,
      do: GenServer.call(session, {:step, plan, index, {:direct, revision, intent}}, 5000)

  def submit_step(_session, _plan, _index, _request), do: {:error, :invalid_request}

  @spec confirm_step(
          session :: pid(),
          plan_id :: String.t(),
          index :: non_neg_integer(),
          proposal_id :: String.t()
        ) :: term()
  def confirm_step(session, plan, index, proposal),
    do: GenServer.call(session, {:step, plan, index, {:confirm, proposal}}, 5000)

  @spec detach(session :: pid()) :: :ok | {:error, atom()}
  def detach(session), do: GenServer.call(session, :detach)

  @impl true
  def init(opts) do
    consumer = Keyword.fetch!(opts, :consumer)
    zone = Keyword.fetch!(opts, :zone)

    state = %{
      consumer: consumer,
      consumer_ref: Process.monitor(consumer),
      zone: zone,
      zone_ref: Process.monitor(zone),
      token: Keyword.fetch!(opts, :token),
      pending: false
    }

    {:ok, state, {:continue, :attach}}
  end

  @impl true
  def handle_continue(:attach, state) do
    case Zone.bind(state.zone, state.token) do
      :ok -> {:noreply, state}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  @impl true
  def handle_call(:detach, {caller, _tag}, %{consumer: caller} = state) do
    :ok = Zone.detach(state.zone)
    {:stop, :normal, :ok, state}
  end

  def handle_call(request, {caller, _tag}, %{consumer: caller} = state) do
    reply =
      case request do
        :view ->
          Zone.view(state.zone)

        {:submit, payload} ->
          Zone.submit(state.zone, payload)

        {:propose, id, intent} ->
          Zone.propose(state.zone, id, intent)

        {:confirm, id, proposal} ->
          Zone.confirm(state.zone, id, proposal)

        {:cancel, proposal} ->
          GenServer.call(state.zone, {:cancel, proposal}, 3000)

        {:step, plan, index, payload} ->
          GenServer.call(state.zone, {:step, plan, index, payload}, 3000)

        _ ->
          {:error, :unsupported_request}
      end

    {:reply, reply, %{state | pending: false}}
  end

  def handle_call(_request, _from, state), do: {:reply, {:error, :unauthorized}, state}

  @impl true
  def handle_info({:zone_changed, zone}, %{zone: zone, pending: false} = state) do
    send(state.consumer, {:genesis_changed, self()})
    {:noreply, %{state | pending: true}}
  end

  def handle_info({:revoked, zone}, %{zone: zone} = state) do
    send(state.consumer, {:genesis_revoked, self()})
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state)
      when ref == state.consumer_ref or ref == state.zone_ref,
      do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}
end
