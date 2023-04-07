import Config

config :botchini,
  environment: Mix.env(),
  ecto_repos: [Botchini.Repo],
  port: System.get_env("PORT", "4000") |> String.to_integer()

config :nostrum,
  audio_timeout: 60_000

config :botchini, Botchini.Scheduler,
  jobs: [
    # Runs every day:
    {"0 0 * * *", {Botchini.Scheduler, :sync_youtube_subscriptions, []}}
  ]

# Configures the endpoint
config :botchini, BotchiniWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: BotchiniWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Botchini.PubSub,
  live_view: [signing_salt: "ZIYuYInA"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.29",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :interaction_data, :guild_id, :channel_id, :user_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :tailwind,
  version: "3.1.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{Mix.env()}.exs"
