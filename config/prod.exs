import Config

config :botchini,
  host: System.get_env("HOST"),
  port: System.get_env("PORT") |> String.to_integer()
