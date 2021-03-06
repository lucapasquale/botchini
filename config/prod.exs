import Config

config :logger,
  level: :info

import_config "prod.secret.exs"
