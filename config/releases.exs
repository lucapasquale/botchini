import Config

config :botchini,
  host: System.get_env("PHX_HOST"),
  port: System.get_env("PORT", "4000") |> String.to_integer(),
  twitch_client_id: System.get_env("TWITCH_CLIENT_ID"),
  twitch_client_secret: System.get_env("TWITCH_CLIENT_SECRET")

config :botchini, Botchini.Repo, url: System.get_env("POSTGRES_URL")

config :nostrum,
  token: System.get_env("DISCORD_TOKEN")
