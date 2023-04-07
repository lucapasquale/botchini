defmodule BotchiniDiscord.Music do
  @moduledoc """
  Handles music connections with Discord
  """

  alias Botchini.Discord

  @spec handle_voice_ready(Nostrum.Struct.Event.VoiceReady.t()) :: any()
  def handle_voice_ready(event) do
    guild = Discord.fetch_guild(Integer.to_string(event.guild_id))

    case Botchini.Music.start_next_track(guild) do
      {:ok, nil} ->
        Nostrum.Voice.stop(guild.discord_guild_id)

      {:ok, track} ->
        IO.inspect(track)

        try_play(event.guild_id, track.play_url, :ytdl, realtime: true)
        |> IO.inspect(label: "try_play")

        Nostrum.Voice.playing?(event.guild_id) |> IO.inspect(label: "playing?")
    end
  end

  @spec handle_voice_update(Nostrum.Struct.Event.SpeakingUpdate.t()) :: any()
  def handle_voice_update(event) when event.speaking == true do
    :noop
  end

  def handle_voice_update(event) do
    guild = Discord.fetch_guild(Integer.to_string(event.guild_id))
    cur_track = Botchini.Music.get_current_track(guild) |> IO.inspect(label: "cur_track")

    if cur_track && cur_track.status == :paused do
      :noop
    else
      case Botchini.Music.start_next_track(guild) do
        {:ok, nil} ->
          Nostrum.Voice.leave_channel(event.guild_id)

        {:ok, track} ->
          try_play(event.guild_id, track.play_url, :ytdl, realtime: true)
          |> IO.inspect(label: "try_play")
      end
    end
  end

  defp try_play(guild_id, url, type, opts) do
    case Nostrum.Voice.play(guild_id, url, type, opts) do
      {:error, _msg} ->
        Process.sleep(100)
        try_play(guild_id, url, type, opts)

      _ ->
        :ok
    end
  end
end
