defmodule BotchiniDiscord.Music do
  @moduledoc """
  Handles music connections with Discord
  """

  require Logger

  alias Botchini.Discord
  alias Botchini.Discord.Schema.Guild
  alias Botchini.Music.PlaybackFailure
  alias Nostrum.Api.Message

  @failure_messages %{
    age_restricted: "it's age-restricted",
    bot_check: "YouTube is blocking the bot",
    forbidden: "YouTube blocked the download",
    rate_limited: "YouTube is rate limiting the bot",
    unavailable: "it's unavailable",
    unsupported_url: "the link isn't supported",
    stream_offline: "the stream is offline"
  }

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

      if event.timed_out && cur_track, do: report_failed_track(cur_track)
    end
  end

  # Nostrum sets timed_out when a track produced no audio at all, usually
  # because yt-dlp or streamlink failed to fetch it. The next track is already
  # playing by now, so diagnosing the failure doesn't hold up the queue
  defp report_failed_track(track) do
    {reason, error} = PlaybackFailure.diagnose(track)

    Logger.warning("Track playback failed",
      event: "track_failed",
      reason: reason,
      error: error,
      track_title: track.title,
      play_url: track.play_url,
      play_type: track.play_type
    )

    emit_track_failure(track, reason)
    notify_failed_track(track, reason)
  end

  defp notify_failed_track(%{discord_channel_id: channel_id} = track, reason)
       when is_binary(channel_id) do
    because =
      case Map.fetch(@failure_messages, reason) do
        {:ok, message} -> " because #{message}"
        :error -> ""
      end

    Message.create(String.to_integer(channel_id), %{
      content: "Couldn't play **#{track.title}**#{because}, skipping it",
      allowed_mentions: :none
    })
  end

  defp notify_failed_track(_track, _reason), do: :noop

  defp emit_track_failure(track, reason) do
    :telemetry.execute([:botchini, :music, :track, :failure], %{count: 1}, %{
      play_type: track.play_type,
      reason: reason
    })
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
    case Nostrum.Voice.play(guild_id, track.play_url, track.play_type) do
      :ok ->
        :telemetry.execute([:botchini, :music, :track, :start], %{count: 1}, %{
          play_type: track.play_type
        })

      {:error, error} ->
        Logger.error("Failed to start track playback",
          event: "track_failed",
          reason: :player_error,
          error: error,
          track_title: track.title
        )

        emit_track_failure(track, :player_error)
    end
  end
end
