import Config

config :logger,
  level: :debug

config :tesla, Tesla.Middleware.Logger, debug: false

config :botchini, Botchini.Repo, url: "postgres://postgres:postgres@localhost/botchini_dev"

import_config "dev.secret.exs"
