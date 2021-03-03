import Config

config :botchini,
  ecto_repos: [Botchini.Repo],
  port: System.get_env("PORT", "3000") |> String.to_integer(),
  host: System.get_env("HOST", "https://96436e6eabc1.ngrok.io"),
  twitch_client_id: System.get_env("TWITCH_CLIENT_ID"),
  twitch_client_secret: System.get_env("TWITCH_CLIENT_SECRET")

config :nostrum,
  token: System.get_env("DISCORD_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic

import_config "#{Mix.env()}.exs"
