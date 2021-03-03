import Config

config :botchini, Botchini.Repo,
  database: "botchini",
  url: "postgres://postgres:postgres@localhost/botchini",
  pool: Ecto.Adapters.SQL.Sandbox

config :nostrum,
  token: "ODE0ODk2ODI2NTY5MTk1NTYx.YDkhzw.5RW0SIBgxnyVdb8zjLT4BJrvutZ"
