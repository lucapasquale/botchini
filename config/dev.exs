import Config

config :logger,
  level: :debug

config :logger, :console,
  format: "\n$time [$level] $levelpad $message $metadata\n",
  metadata: [:interaction_data, :guild_id, :channel_id, :user_id, :error_message]

config :tesla, Tesla.Middleware.Logger, debug: false

config :botchini, Botchini.Repo, url: "postgres://postgres:postgres@localhost/botchini_dev"

import_config "dev.secret.exs"
