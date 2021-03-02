defmodule Botchini.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Botchini.Repo,
      {Plug.Cowboy,
       scheme: :https,
       plug: Botchini.Router,
       options: [port: Application.fetch_env!(:botchini, :port)]},
      BotchiniDiscord.Consumer,
      Botchini.Twitch.AuthMiddleware
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Botchini.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
