import Config

config :logger,
  level: :debug

config :botchini,
  port: 3000

config :botchini, Botchini.Repo,
  database: "botchini",
  url: "postgres://postgres:postgres@localhost/botchini_dev",
  pool: Ecto.Adapters.SQL.Sandbox

import_config "dev.secret.exs"
