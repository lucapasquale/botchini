# Botchini

Discord Bot with Twitch and YouTube integrations for creator notifications!

Get messages when a Twitch user starts streaming, or when a YouTube channel posts a new video or starts a live.

Uses modern features like [Slash Commands](https://blog.discord.com/slash-commands-are-here-8db0a385d9e6?gi=cb5c18566e7) and [Message Components](https://discord.com/developers/docs/interactions/message-components)

## [Add it to your server](https://discord.com/api/oauth2/authorize?client_id=814896826569195561&permissions=2048&scope=bot%20applications.commands)

![image](https://user-images.githubusercontent.com/15659967/121437344-89bb7180-c958-11eb-9d2f-034cf8b5f179.png)

## Slash Commands

 - Common
    - `/about` : Bot status with uptime, memory usage and more
 - Creators
    - `/info <service> <term>` : Information about a Twitch user or YouTube channel
    - `/follow <service> <term>` : Follow a creator and get notified when it starts streaming or uploads a video
    - `/unfollow <service> <term>` : Stops following a creator
    - `/list` : Lists all creators being followed on the server

## Installation

Copy the sample environment sample file into a secrets file:

```bash
cat config/dev.secret-sample.exs > config/dev.secret.exs
```

Run `mix setup` to install all dependencies and run the database migrations

### Host

For receiving and registering to webhooks locally, you need a public url that can reach your machine. You can use start a proxy with [ngrok http $PORT](https://ngrok.com/), then copy the url generated into the `:host` config.

### Discord

Grab your bot's token from [Discord Applications](https://discord.com/developers/applications) on `Your application > Bot > Click to reveal token`

### YouTube

Create an account on [Google Cloud Platform](https://console.cloud.google.com), and create a new API Key for your bot. You can limit the key to only have access to `YouTube Data API v3`

### Twitch

To be able to search and receive webhooks from streams, you need to register an application on the [Twitch Applications](https://dev.twitch.tv/console/apps). After that, you'll be able to get the `client_id` and `client_secret` tokens.

## Running locally

After all necessary values are on `config/dev.secret.exs`, run the bot with: `mix phx.server`. It will reload automatically when you update a file.

## Running in production

The bot needs the following env_vars:

 - `PORT` : Port to run on. Defaults to 4000
 - `PHX_HOST` : The endpoint your bot is running on, without `https://`
 - `DATABASE_URL` : The url to connect to your postgres db
 - `DISCORD_TOKEN` : Token for your Discord Bot
 - `YOUTUBE_API_KEY` : YouTube API key
 - `TWITCH_CLIENT_ID` : Client ID for your Twitch application
 - `TWITCH_CLIENT_SECRET` : Client Secret for your Twitch application
