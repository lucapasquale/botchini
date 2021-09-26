defmodule BotchiniDiscord.Voice do
  @moduledoc """
  Handles voice connections with Discord
  """

  alias Botchini.{Discord, Voice}

  @spec handle_voice_ready(Nostrum.Struct.Event.VoiceReady.t()) :: any()
  def handle_voice_ready(event) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(event.guild_id))

    case Voice.start_next_track(guild) do
      nil ->
        Nostrum.Voice.stop(guild.discord_guild_id)

      track ->
        Nostrum.Voice.play(event.guild_id, track.play_url, :ytdl)
    end
  end

  @spec handle_voice_update(Nostrum.Struct.Event.SpeakingUpdate.t()) :: any()
  def handle_voice_update(event) when event.speaking do
    :noop
  end

  def handle_voice_update(event) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(event.guild_id))

    case Voice.start_next_track(guild) do
      nil ->
        Nostrum.Voice.leave_channel(event.guild_id)

      track ->
        Nostrum.Voice.play(event.guild_id, track.play_url, :ytdl)
    end
  end
end
