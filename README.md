# Botchini

Discord Bot with Twitch integration for stream notifications!

Uses modern features like [Slash Commands](https://blog.discord.com/slash-commands-are-here-8db0a385d9e6?gi=cb5c18566e7) and [Message Components](https://discord.com/developers/docs/interactions/message-components)

## [Add it to your server](https://discord.com/api/oauth2/authorize?client_id=814896826569195561&permissions=2048&scope=bot%20applications.commands)

![image](https://user-images.githubusercontent.com/15659967/121437344-89bb7180-c958-11eb-9d2f-034cf8b5f179.png)

## Slash Commands

 - `/info` : Bot status with uptime, memory usage and more
 - `/stream <stream_code>` : Information about a Twitch channel
 - `/follow <stream_code>` : Follow a channel and get notified when it starts streaming
 - `/unfollow <stream_code>` : Stops following a channel
 - `/following` : Lists all channels currently followed on the server

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
