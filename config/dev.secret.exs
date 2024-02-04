import Config

config :botchini,
  # Use `ngrok http 3010` to generate an url that connects to your localhost
  host: "https://abcd1234.ngrok.io",
  # Discord application id
  discord_app_id: "816826340216668200",
  # YouTube API credentials
  youtube_api_key: "AIzaSyAOh92sRMneDy1e0snXgDrritZySzLOc6s",
  youtube_webhook_secret: "CGnGvBb.Zyrt4Ps8_Ubb",
  # Twitch API credentials
  twitch_client_id: "z4iig300fz0i3wmm7c3oojb8dg8ui1",
  twitch_client_secret: "dqwxx908yclaxto85ythei3y817x7b",
  twitch_webhook_secret: "gNsLHJbE2W3XkFh89@qw",
  # This makes the slash commands update instanly, since discord takes about one hour
  # to sync the commands globally. Copy from the server you are testing on
  test_guild_id: 123_123_123_123_123_123

config :nostrum,
  # Create a separarate development account on discord API
  token: "ODE2ODI2MzQwMjE2NjY4MjAw.YEAmzw.-BVjnOVNIbKA1Lfb25Zz2txHvR4"
