# Botchini

Discord Bot with Twitch integration for stream notifications!

## Commands

 - `!ping` : Check if the bot is alive, and how long it takes to respond
 - `!status` : Information about the bot, uptime, memory usage, etc.

 - `!stream add <stream_code>` : Add a stream to be notified in the current channel when that stream starts
 - `!stream remove <stream_code>` : Remove a stream from your notifications
 - `!stream list` : Lists all streams currently being followed in this channel

## Installation

Run `mix deps.get` to install all dependencies

## Running

To run this bot, you'll need the following env_vars:

 - `PORT` : Port to run on. Defaults to 3010
 - `HOST` : The url your bot is running on, so ir can receive webhooks from Twitch. For local development, you can use [ngrok](https://ngrok.com/)
 - `POSTGRES_URL` : The url to connect to your postgres db
 - `DISCORD_TOKEN` : Token for your Discord Bot
 - `TWITCH_CLIENT_ID` : Client ID for your Twitch application
 - `TWITCH_CLIENT_SECRET` : Client Secret for your Twitch application

After you export this env_vars on your shell, run the migrations with:

`mix ecto.migrate`

And then, run the bot with:

`mix run --no-halt`

Or, if you want to use Docker:

`docker build -t botchini:latest .`
`sudo docker run --rm -p 3010:3010 botchini:latest`
