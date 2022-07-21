defmodule Botchini.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        Botchini.Repo,
        # Start the Telemetry supervisor
        BotchiniWeb.Telemetry,
        # Start the PubSub system
        {Phoenix.PubSub, name: Botchini.PubSub},
        # Start the Endpoint (http/https)
        BotchiniWeb.Endpoint,
        BotchiniWeb.Cache,
        # Twitch auth middleware
        Botchini.Services.Twitch.AuthMiddleware,
        # Youtube videos posted cache
        Botchini.Services.Youtube.VideoCache
      ] ++
        if Application.fetch_env!(:botchini, :environment) != :test,
          do: [BotchiniDiscord.Consumer],
          else: []

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Botchini.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
