defmodule BotchiniDiscord.Music do
  @moduledoc """
  Handles music connections with Discord
  """

  alias Botchini.Discord
  alias Botchini.Discord.Schema.Guild

  @spec handle_voice_ready(Nostrum.Struct.Event.VoiceReady.t()) :: any()
  def handle_voice_ready(event) do
    guild = Discord.fetch_guild(Integer.to_string(event.guild_id))

    case Botchini.Music.start_next_track(guild) do
      {:ok, nil} ->
        Nostrum.Voice.stop(guild.discord_guild_id)
        Nostrum.Voice.leave_channel(event.guild_id)

      {:ok, track} ->
        play_track(event.guild_id, track)
    end
  end

  @spec handle_voice_update(Nostrum.Struct.Event.SpeakingUpdate.t()) :: any()
  def handle_voice_update(event) when event.speaking == true do
    :noop
  end

  def handle_voice_update(event) do
    guild = Discord.fetch_guild(Integer.to_string(event.guild_id))
    cur_track = Botchini.Music.get_current_track(guild)

    if cur_track && cur_track.status == :paused do
      :noop
    else
      play_next_track(guild)
    end
  end

  @doc """
  Marks the current track as done and plays the next one, leaving the voice channel when the queue is empty
  """
  @spec play_next_track(Guild.t()) :: any()
  def play_next_track(guild) do
    guild_id = String.to_integer(guild.discord_guild_id)

    case Botchini.Music.start_next_track(guild) do
      {:ok, nil} ->
        Nostrum.Voice.leave_channel(guild_id)

      {:ok, track} ->
        play_track(guild_id, track)
    end
  end

  defp play_track(guild_id, track) do
    Nostrum.Voice.play(guild_id, track.play_url, track.play_type)
  end
end
