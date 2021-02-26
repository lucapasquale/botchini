import Config

# config :logger,
#   level: :warn

config :nostrum,
  token: System.get_env("DISCORD_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic
