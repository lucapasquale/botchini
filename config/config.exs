import Config

config :botchini,
  environment: Mix.env(),
  ecto_repos: [Botchini.Repo],
  host: System.get_env("HOST"),
  port: System.get_env("PORT", "3010") |> String.to_integer(),
  twitch_client_id: System.get_env("TWITCH_CLIENT_ID"),
  twitch_client_secret: System.get_env("TWITCH_CLIENT_SECRET")

config :botchini, Botchini.Repo,
  database: "botchini",
  url: System.get_env("POSTGRES_URL")

config :nostrum,
  token: System.get_env("DISCORD_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic

import_config "#{Mix.env()}.exs"
