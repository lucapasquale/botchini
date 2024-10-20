# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :botchini,
  environment: Mix.env(),
  ecto_repos: [Botchini.Repo],
  port: System.get_env("PORT", "4000") |> String.to_integer()

config :nostrum,
  youtubedl: "yt-dlp",
  streamlink: false,
  audio_timeout: 60_000

config :botchini, Botchini.Scheduler,
  jobs: [
    # Runs every day:
    {"0 0 * * *", {Botchini.Scheduler, :sync_youtube_subscriptions, []}}
  ]

# Configures the endpoint
config :botchini, BotchiniWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BotchiniWeb.ErrorHTML, json: BotchiniWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Botchini.PubSub,
  live_view: [signing_salt: "wHm7OOrG"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  botchini: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  botchini: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :interaction_data, :guild_id, :channel_id, :user_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
