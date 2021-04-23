import Config

config :logger,
  level: :info,
  backends: [LogflareLogger.HttpBackend]
