import Config

config :logger,
  level: :debug,
  backends: [Ink]

config :logger, Ink,
  name: "botchini",
  metadata: [:error, :interaction, :response]

config :botchini, Botchini.Repo, url: "postgres://postgres:postgres@localhost/botchini_dev"

import_config "dev.secret.exs"
