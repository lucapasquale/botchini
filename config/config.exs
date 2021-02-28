import Config

# config :logger,
#   level: :info

config :botchini, Botchini.Repo,
  database: "botchini",
  url: System.get_env("POSTGRES_URL")

config :botchini,
  ecto_repos: [Botchini.Repo]

config :botchini,
  port: System.get_env("PORT") || 3000,
  host: System.get_env("HOST") || "https://3b57177cf545.ngrok.io"

config :botchini,
  twitch_url: "https://api.twitch.tv/helix",
  twitch_headers: [
    {"client-id", System.get_env("TWITCH_CLIENT_ID")},
    {"authorization", "Bearer " <> System.get_env("TWITCH_TOKEN")}
  ]

config :nostrum,
  token: System.get_env("DISCORD_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic
