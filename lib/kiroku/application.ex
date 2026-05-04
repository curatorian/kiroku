defmodule Kiroku.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KirokuWeb.Telemetry,
      Kiroku.Repo,
      {DNSCluster, query: Application.get_env(:kiroku, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Kiroku.PubSub},
      {Oban, Application.fetch_env!(:kiroku, Oban)},
      # LegacyRepo (MSSQL) is started manually in the import Mix task — NOT here
      KirokuWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kiroku.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KirokuWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
