import Config

config :botchini, Botchini.Repo,
  database: "botchini",
  url: "postgres://postgres:postgres@localhost/botchini_test",
  pool: Ecto.Adapters.SQL.Sandbox
