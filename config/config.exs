import Config

config :botchini, Botchini.Repo,
  database: "botchini",
  username: "botchini",
  password: System.get_env("POSTGRES_PASS"),
  hostname: System.get_env("POSTGRES_HOST")

config :botchini, ecto_repos: [Botchini.Repo]

config :logger,
  level: :info

config :nostrum,
  token: System.get_env("DISCORD_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic
