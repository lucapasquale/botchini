import Config

config :botchini,
  environment: Mix.env(),
  ecto_repos: [Botchini.Repo],
  port: System.get_env("PORT", "3010") |> String.to_integer()

config :porcelain,
  driver: Porcelain.Driver.Basic

import_config "#{Mix.env()}.exs"
