import Config

# Note we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the `mix assets.deploy` task,
# which you should run after static files are built and
# before starting your production server.
config :botchini, BotchiniWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Botchini.Finch

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

config :sentry,
  environment_name: Mix.env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

# Configures Prometheus/Grafana
config :botchini, Botchini.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: [
    host: System.get_env("GRAFANA_HOST", "http://localhost:3000"),
    # Authenticate via Basic Auth
    username: System.get_env("GRAFANA_USERNAME", "admin"),
    password: System.get_env("GRAFANA_PASSWORD"),
    upload_dashboards_on_start: true
  ],
  metrics_server: :disabled

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
