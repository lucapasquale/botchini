import Config

config :botchini,
  # Use `ngrok http 3010` to generate an url that connects to your localhost
  host: "https://abcd1234.ngrok.io",
  # Create a separarate development account on Twitch API
  twitch_client_id: "YOUR_TWITCH_CLIENT_ID",
  twitch_client_secret: "YOUR_TWITCH_CLIENT_SECRET",
  # This makes the slash commands update instanly, since discord takes about one hour
  # to sync the commands globally. Copy from the server you are testing on
  test_guild_id: 123_123_123_123_123_123

config :nostrum,
  # Create a separarate development account on discord API
  token: "YOUR_DISCORD_TOKEN"
