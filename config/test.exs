import Config

config :botchini, Botchini.Repo,
  url: "postgres://postgres:postgres@localhost/botchini_test",
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :botchini, BotchiniWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "vojhNbUnH62IJbsnFjMMEtcebSSeIXyEZNd77fkjc/EAUQS2LDn/vxgc5TDUtaUr",
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
