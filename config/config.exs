import Config

# config :logger,
#   level: :info

config :botchini, Botchini.Repo,
  database: "botchini",
  url: System.get_env("POSTGRES_URL")

config :botchini,
  port: System.get_env("PORT", "3000") |> String.to_integer(),
  host: System.get_env("HOST", "https://aa978acc2363.ngrok.io"),
  ecto_repos: [Botchini.Repo],
  twitch_client_id: System.get_env("TWITCH_CLIENT_ID"),
  twitch_client_secret: System.get_env("TWITCH_CLIENT_SECRET")

config :nostrum,
  token: System.get_env("DISCORD_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic
