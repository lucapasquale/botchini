defmodule Botchini.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        BotchiniWeb.Telemetry,
        Botchini.Repo,
        Botchini.Cache,
        Botchini.Scheduler,
        Botchini.Services.Twitch.AuthMiddleware,
        {DNSCluster, query: Application.get_env(:botchini, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Botchini.PubSub},
         # Start the Finch HTTP client for sending emails
        {Finch, name: Botchini.Finch},
        # Start a worker by calling: Botchini.Worker.start_link(arg)
        # {Botchini.Worker, arg},
        # Start to serve requests, typically the last entry
        BotchiniWeb.Endpoint,
      ]
      |> start_nostrum(Application.fetch_env!(:botchini, :environment))

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Botchini.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_nostrum(children, :test), do: children
  defp start_nostrum(children, _env), do: children ++ [BotchiniDiscord.Consumer]

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BotchiniWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
