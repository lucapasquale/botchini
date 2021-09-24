defmodule BotchiniDiscord.Consumer do
  @moduledoc """
  Consumes events from the Discord API connection
  """

  require Logger
  use Nostrum.Consumer

  alias Botchini.Discord
  alias BotchiniDiscord.Interactions

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _data, _ws_state}) do
    Interactions.register_commands()

    version = to_string(Application.spec(:botchini, :vsn))
    Nostrum.Api.update_status(:online, "on v#{version}")

    Logger.info("Bot started!")
  end

  def handle_event({:GUILD_CREATE, {guild}, _ws_state}) do
    Discord.upsert_guild(Integer.to_string(guild.id))
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    Interactions.handle_interaction(interaction)
  end

  def handle_event({:VOICE_READY, event, _ws_state}) do
    IO.inspect(event, label: "voice ready")
    Nostrum.Voice.play(event.guild_id, "https://www.youtube.com/watch?v=7ijMDQgvW0o", :ytdl)
  end

  def handle_event({event, _data, _ws}) do
    IO.inspect(event, label: "new event")
    :noop
  end
end
