# Botchini

Discord Bot with Twitch integration for stream notifications!

Uses modern features like [Slash Commands](https://blog.discord.com/slash-commands-are-here-8db0a385d9e6?gi=cb5c18566e7) and [Message Components](https://discord.com/developers/docs/interactions/message-components)

## [Add it to your server](https://discord.com/api/oauth2/authorize?client_id=814896826569195561&permissions=2048&scope=bot%20applications.commands)

![image](https://user-images.githubusercontent.com/15659967/121437344-89bb7180-c958-11eb-9d2f-034cf8b5f179.png)

## Slash Commands

 - Common
    - `/info` : Bot status with uptime, memory usage and more
 - Twitch
    - `/stream <stream_code>` : Information about a Twitch channel
    - `/follow <stream_code>` : Follow a channel and get notified when it starts streaming
    - `/unfollow <stream_code>` : Stops following a channel
    - `/list` : Lists all channels currently followed on the server

## Installation

Copy the sample environment sample file into a secrets file:

```bash
cat config/dev.secret-sample.exs > config/dev.secret.exs
```

Run `mix deps.get` to install all dependencies, and `mix ecto.migrate` to run the database migrations

### Discord

Grab your bot's token from [Discord Applications](https://discord.com/developers/applications) on `Your application > Bot > Click to reveal token`

### Twitch commands

For receiving and registering webhooks with Twitch, you need a url for the webhook to reach your machine. Locally you can use start a proxy with [ngrok http $PORT](https://ngrok.com/), then copy the url generated into the `:host` config.

## Running locally

After all necessary values are on `config/dev.secret.exs`, run the bot with: `mix run --no-halt` or `iex -S mix`. It will reload automatically when you update a file.

## Running in production

The bot needs the following env_vars:

 - `PORT` : Port to run on. Defaults to 4000
 - `PHX_HOST` : The url your bot is running on, so ir can receive webhooks from Twitch
 - `DATABASE_URL` : The url to connect to your postgres db
 - `DISCORD_TOKEN` : Token for your Discord Bot
 - `TWITCH_CLIENT_ID` : Client ID for your Twitch application
 - `TWITCH_CLIENT_SECRET` : Client Secret for your Twitch application
