import Config

config :botchini,
  environment: Mix.env(),
  ecto_repos: [Botchini.Repo],
  port: System.get_env("PORT", "3010") |> String.to_integer()

config :logger, :console,
  format: "\n$time [$level] $levelpad $message $metadata\n",
  metadata: [:interaction_data, :guild_id, :channel_id, :user_id, :error_message]

config :tesla, adapter: Tesla.Adapter.Hackney

config :porcelain, driver: Porcelain.Driver.Basic

import_config "#{Mix.env()}.exs"
