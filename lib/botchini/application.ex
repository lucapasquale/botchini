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
        Botchini.Cache,
        Botchini.Scheduler,
        # Start the Telemetry supervisor
        BotchiniWeb.Telemetry,
        # Start the PubSub system
        {Phoenix.PubSub, name: Botchini.PubSub},
        BotchiniWeb.Endpoint,
        # Twitch auth middleware
        Botchini.Services.Twitch.AuthMiddleware
      ]
      |> start_nostrum(Application.fetch_env!(:botchini, :environment))

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Botchini.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_nostrum(children, :test), do: children
  defp start_nostrum(children, _env), do: children ++ [BotchiniDiscord.Consumer]
end
