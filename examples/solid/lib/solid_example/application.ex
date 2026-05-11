defmodule SolidExample.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SolidExampleWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:solid_example, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SolidExample.PubSub},
      SolidExampleWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: SolidExample.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SolidExampleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
