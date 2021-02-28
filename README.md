# Botchini

Discord Bot with Twitch integration for stream notifications!

## Commands

 - `!ping` -> Check if the bot is alive, and how long it takes to respond
 - `!stream add <stream_code>` -> Add a stream to be notified in the current channel when that stream starts
 - `!stream remove <stream_code>` -> Remove a stream from your notifications

## Installation

Run `mix deps.get` to install all dependencies

## Running

To run this bot, you'll need the following env_vars:

 - `DISCORD_TOKEN`: Token for your Discord Bot
 - `POSTGRES_URL`: The url to connect to your postgres db
 - `TWITCH_CLIENT_ID`: Client ID for your Twitch application
 - `TWITCH_TOKEN`: Access Token for your Twitch application (for now it doesn't re-authenticate, so it needs to be provided a new one everytime you build/run )

After you export this env_vars on your shell, run the migrations with:

`mix ecto.migrate`

And then, run the bot with:

`mix run --no-halt`

