defmodule Botchini.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Setup OpenTelemetry instrumentation for Phoenix and Ecto
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:botchini, :repo])

    children =
      [
        Botchini.PromEx,
        BotchiniWeb.Telemetry,
        Botchini.LokiLogger,
        Botchini.Repo,
        Botchini.Cache,
        Botchini.Scheduler,
        {DNSCluster, query: Application.get_env(:botchini, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Botchini.PubSub},
        # Start the Finch HTTP client for sending emails
        {Finch, name: Botchini.Finch},
        # Twitch auth middleware
        Botchini.Services.Twitch.AuthMiddleware,
        # Screen sharing rooms
        {Registry, keys: :unique, name: Botchini.Screens.Registry},
        {DynamicSupervisor, name: Botchini.Screens.RoomSupervisor, strategy: :one_for_one},
        Botchini.Screens.Presence,
        # Start a worker by calling: Botchini.Worker.start_link(arg)
        # {Botchini.Worker, arg},
        # Start to serve requests, typically the last entry
        BotchiniWeb.Endpoint
      ]
      |> start_nostrum(Application.fetch_env!(:botchini, :environment))
      |> start_metrics_server(Application.get_env(:botchini, :metrics_port))

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Botchini.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_metrics_server(children, nil), do: children

  defp start_metrics_server(children, port) do
    children ++ [{Bandit, plug: BotchiniWeb.MetricsPlug, port: port}]
  end

  defp start_nostrum(children, :test), do: children

  defp start_nostrum(children, _env) do
    bot_options = %{
      consumer: BotchiniDiscord.Consumer,
      intents: [:guilds, :guild_voice_states],
      wrapped_token: fn -> Application.fetch_env!(:botchini, :discord_token) end
    }

    children ++ [{Nostrum.Bot, bot_options}, BotchiniDiscord.Screens.Announcer]
  end
end
