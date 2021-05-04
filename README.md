# Botchini

Discord Bot with Twitch integration for stream notifications!

## [Add it to your server](https://discord.com/api/oauth2/authorize?client_id=814896826569195561&permissions=2048&scope=bot%20applications.commands)

![image](https://user-images.githubusercontent.com/15659967/110556115-a5766800-811c-11eb-940b-95cd01acaa5c.png)

## Slash Commands

 - `/info` : Information about the bot, uptime, memory usage, etc.
 - `/stream <stream_code>` : Information about a stream
 - `/follow <stream_code>` : Follow a stream to be notified when the channel starts streaming
 - `/unfollow <stream_code>` : Stop following a channel
 - `/following` : Lists all channels currently followed

## Installation

Run `mix deps.get` to install all dependencies, and `mix ecto.migrate` to run the database migrations

## Running

To run this bot, you'll need the following env_vars:

 - `PORT` : Port to run on. Defaults to 3010
 - `HOST` : The url your bot is running on, so ir can receive webhooks from Twitch. For local development, you can use [ngrok](https://ngrok.com/)
 - `POSTGRES_URL` : The url to connect to your postgres db
 - `DISCORD_TOKEN` : Token for your Discord Bot
 - `TWITCH_CLIENT_ID` : Client ID for your Twitch application
 - `TWITCH_CLIENT_SECRET` : Client Secret for your Twitch application

Then, run the bot with:

`mix run --no-halt`

Or, if you want to use Docker:

`docker build -t botchini:latest .`

`docker run --rm -p 3010:3010 botchini:latest`
