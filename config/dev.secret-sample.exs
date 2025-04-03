import Config

config :botchini,
  # Use `ngrok http 3010` to generate an url that connects to your localhost
  host: "https://abcd1234.ngrok.io",
  # Discord application id
  discord_app_id: "BOT_APP_ID",
  # YouTube API credentials
  youtube_api_key: "YOUTUBE_API_KEY",
  youtube_webhook_secret: "YOUTUBE_WEBHOOK_SECRET",
  # Twitch API credentials
  twitch_client_id: "YOUR_TWITCH_CLIENT_ID",
  twitch_client_secret: "YOUR_TWITCH_CLIENT_SECRET",
  twitch_webhook_secret: "TWITCH_WEBHOOK_SECRET",
  # This makes the slash commands update instanly, since discord takes about one hour
  # to sync the commands globally. Copy from the server you are testing on
  test_guild_ids: ["123123123123123123,456456456456456456"]

config :nostrum,
  # Create a separarate development account on discord API
  token: "YOUR_DISCORD_TOKEN"
