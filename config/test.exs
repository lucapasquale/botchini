import Config

config :botchini, Botchini.Repo,
  database: "botchini",
  url: "postgres://postgres:postgres@localhost/botchini",
  pool: Ecto.Adapters.SQL.Sandbox

config :nostrum,
  token: "fake_token"
