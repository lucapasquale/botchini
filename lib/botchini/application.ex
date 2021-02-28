defmodule Botchini.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Botchini.Repo,
      Botchini.Consumer,
      {Plug.Cowboy,
       scheme: :http,
       plug: Botchini.Router,
       options: [port: Application.fetch_env!(:botchini, :port)]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Botchini.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
