import Config

# config :logger,
#   level: :info

config :botchini, Botchini.Repo,
  database: "botchini",
  url: System.get_env("POSTGRES_URL")

config :botchini,
  ecto_repos: [Botchini.Repo]

config :botchini,
  twitch_url: "https://api.twitch.tv/helix",
  twitch_headers: [
    {"client-id", System.get_env("TWITCH_CLIENT_ID")},
    {"authorization", "Bearer " <> System.get_env("TWITCH_TOKEN")}
  ]

config :botchini, Botchini.Scheduler,
  jobs: [
    # Every minute
    {"* * * * *", {Botchini.Crons.Twitch, :sync_streams, []}}
  ]

config :nostrum,
  token: System.get_env("DISCORD_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic
