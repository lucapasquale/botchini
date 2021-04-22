import Config

config :logger,
  level: :info,
  backends: [Ink]

config :logger, Ink, name: "botchini"
