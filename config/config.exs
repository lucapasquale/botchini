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
  audio_timeout: 60_000

# Port serving the Prometheus metrics scraped by Grafana Alloy, nil disables it
config :botchini, :metrics_port, 9568

config :botchini, Botchini.Scheduler,
  jobs: [
    # Runs every day:
    {"0 0 * * *", {Botchini.Scheduler, :sync_youtube_subscriptions, []}}
  ]

# Screen sharing WebRTC, see Botchini.Screens for all options. STUN lets the
# server and browsers find their public addresses
config :botchini, Botchini.Screens, ice_servers: [%{urls: "stun:stun.l.google.com:19302"}]

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
  version: "0.28.2",
  botchini: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  botchini: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :interaction_data,
    :guild_id,
    :channel_id,
    :user_id,
    :event,
    :reason,
    :error,
    :track_title,
    :play_url,
    :play_type,
    :screen_room_id,
    :screen_title,
    :screen_owner_id,
    :screen_owner_name,
    :viewer_count,
    :creator,
    :follower_count,
    :video_id,
    :twitch_user_id,
    :version,
    :method,
    :url,
    :status
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# OpenTelemetry - disabled by default, enabled in prod
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :none

# PromEx
config :botchini, Botchini.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
