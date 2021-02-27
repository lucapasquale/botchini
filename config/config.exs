import Config

config :logger,
  level: :info

config :botchini, Botchini.Repo,
  database: "botchini",
  username: "botchini",
  password: System.get_env("POSTGRES_PASS"),
  hostname: System.get_env("POSTGRES_HOST")

config :botchini, ecto_repos: [Botchini.Repo]

config :botchini, Botchini.Scheduler,
  jobs: [
    # Every minute
    {"* * * * *", {Botchini.Crons.Twitch, :sync_streams, []}}
  ]

config :nostrum,
  token: System.get_env("DISCORD_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic
