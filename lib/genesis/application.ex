defmodule Genesis.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GenesisWeb.Telemetry,
      Genesis.Repo,
      {Oban, Application.fetch_env!(:genesis, Oban)},
      {DNSCluster, query: Application.get_env(:genesis, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Genesis.PubSub},
      # Start a worker by calling: Genesis.Worker.start_link(arg)
      # {Genesis.Worker, arg},
      # Start to serve requests, typically the last entry
      GenesisWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Genesis.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GenesisWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
