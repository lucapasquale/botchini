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

 - `PORT`: Port to run on. Defaults to 3000
 - `HOST`: The url your bot is running on, so we can receive webhooks from Twitch
 - `DISCORD_TOKEN`: Token for your Discord Bot
 - `POSTGRES_URL`: The url to connect to your postgres db
 - `TWITCH_CLIENT_ID`: Client ID for your Twitch application
 - `TWITCH_CLIENT_SECRET`: Client Secret for your Twitch application

After you export this env_vars on your shell, run the migrations with:

`mix ecto.migrate`

And then, run the bot with:

`mix run --no-halt`

