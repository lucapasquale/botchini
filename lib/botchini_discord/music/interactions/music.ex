defmodule BotchiniDiscord.Music.Interactions.Music do
  @moduledoc """
  Handles /music slash command
  """

  alias Nostrum.Cache.GuildCache
  alias Nostrum.Constants.{ApplicationCommandOptionType, InteractionCallbackType, InteractionType}
  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.{Discord, Music, Services}
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}
  alias BotchiniDiscord.Music, as: DiscordMusic
  alias BotchiniDiscord.Music.Responses.Components

  @behaviour InteractionBehaviour

  @youtube_hosts [
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be"
  ]

  @impl BotchiniDiscord.InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "music",
      description: "Play music on discord!",
      options: [
        %{
          name: "play",
          description: "Play a song",
          type: ApplicationCommandOptionType.sub_command(),
          options: [
            %{
              type: ApplicationCommandOptionType.string(),
              required: true,
              name: "term",
              description: "YouTube URL or search term"
            }
          ]
        },
        %{
          name: "pause",
          description: "Pause current song",
          type: ApplicationCommandOptionType.sub_command()
        },
        %{
          name: "resume",
          description: "Resume current song",
          type: ApplicationCommandOptionType.sub_command()
        },
        %{
          name: "skip",
          description: "Skip current song",
          type: ApplicationCommandOptionType.sub_command()
        },
        %{
          name: "stop",
          description: "Stop playing",
          type: ApplicationCommandOptionType.sub_command()
        },
        %{
          name: "queue",
          description: "Next songs",
          type: ApplicationCommandOptionType.sub_command()
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, _options) when is_nil(interaction.guild_id) do
    %{
      type: InteractionCallbackType.channel_message_with_source(),
      data: %{content: "Cannot use this command from outside a guild!"}
    }
  end

  def handle_interaction(interaction, options) do
    cond do
      Helpers.get_option(options, "play") ->
        handle_play(interaction, options)

      Helpers.get_option(options, "pause") ->
        handle_pause(interaction, options)

      Helpers.get_option(options, "resume") ->
        handle_resume(interaction, options)

      Helpers.get_option(options, "skip") ->
        handle_skip(interaction, options)

      Helpers.get_option(options, "stop") ->
        handle_stop(interaction, options)

      Helpers.get_option(options, "queue") ->
        handle_queue(interaction, options)

      true ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Invalid command"}
        }
    end
  end

  defp handle_play(interaction, options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    case get_voice_channel_of_msg(interaction) do
      nil ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Please enter a voice channel first!"}
        }

      voice_channel_id ->
        {term, _autocomplete} = Helpers.get_option!(options, "term")

        Music.insert_track(
          %{
            term: term,
            play_url: get_play_url_from_term(term),
            play_type: get_play_type_from_term(term),
            discord_channel_id: Integer.to_string(interaction.channel_id)
          },
          guild
        )

        if Nostrum.Voice.get_channel_id(interaction.guild_id) != voice_channel_id do
          Nostrum.Voice.join_channel(interaction.guild_id, voice_channel_id)
        end

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{
            content: "Added **#{term}** to queue",
            components: [Components.pause_controls()]
          }
        }
    end
  end

  defp handle_pause(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    case Music.pause(guild) do
      {:ok, nil} ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Not currently playing"}
        }

      {:ok, cur_track} ->
        Nostrum.Voice.pause(interaction.guild_id)

        update_or_reply(interaction, %{
          content: "Paused **#{cur_track.title}**",
          components: [Components.resume_controls()]
        })
    end
  end

  defp handle_resume(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))
    cur_track = Music.get_current_track(guild)

    if is_nil(cur_track) || cur_track.status != :paused do
      %{
        type: InteractionCallbackType.channel_message_with_source(),
        data: %{content: "No song to resume!"}
      }
    else
      Music.resume(guild)
      Nostrum.Voice.resume(interaction.guild_id)

      update_or_reply(interaction, %{
        content: "Resuming **#{cur_track.title}**",
        components: [Components.pause_controls()]
      })
    end
  end

  defp handle_skip(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    case Music.get_next_track(guild) do
      nil ->
        Music.clear_queue(guild)
        Nostrum.Voice.stop(interaction.guild_id)
        Nostrum.Voice.leave_channel(interaction.guild_id)

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "No song in queue, stopping"}
        }

      track ->
        skip_current_track(interaction.guild_id, guild)

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{
            content: "Skipping to next song: **#{track.title}**",
            components: [Components.pause_controls()]
          }
        }
    end
  end

  defp handle_stop(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    Music.clear_queue(guild)
    Nostrum.Voice.stop(interaction.guild_id)
    Nostrum.Voice.leave_channel(interaction.guild_id)

    %{
      type: InteractionCallbackType.channel_message_with_source(),
      data: %{content: "Stopped playing"}
    }
  end

  defp handle_queue(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    case Music.get_next_tracks(guild) do
      tracks when tracks == [] ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Queue is empty"}
        }

      tracks ->
        list_message =
          tracks
          |> Enum.map_join("\n", fn track -> " - #{track.title}" end)

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{
            content: """
            Next songs:
            #{list_message}
            """
          }
        }
    end
  end

  # A paused track has no running player for Voice.stop to end (and no speaking
  # update to trigger the next track), so start the next track directly
  defp skip_current_track(guild_id, guild) do
    case Music.get_current_track(guild) do
      %{status: :paused} -> DiscordMusic.play_next_track(guild)
      _ -> Nostrum.Voice.stop(guild_id)
    end
  end

  # Buttons edit the message they belong to, while slash commands must reply with a new one
  defp update_or_reply(interaction, data) do
    type =
      if interaction.type == InteractionType.message_component(),
        do: InteractionCallbackType.update_message(),
        else: InteractionCallbackType.channel_message_with_source()

    %{type: type, data: data}
  end

  defp get_voice_channel_of_msg(interaction) do
    interaction.guild_id
    |> GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(%{}, fn v -> v.user_id == interaction.member.user_id end)
    |> Map.get(:channel_id)
  end

  defp get_play_url_from_term(term) do
    if String.starts_with?(term, "http") do
      term
    else
      "ytsearch:#{term}"
    end
  end

  defp get_play_type_from_term(term) do
    cond do
      String.starts_with?(term, "https://www.twitch.tv") ->
        :stream

      youtube_url?(term) ->
        youtube_play_type(term)

      true ->
        :ytdl
    end
  end

  defp youtube_url?(term) do
    URI.parse(term).host in @youtube_hosts
  end

  # Live streams are played with streamlink, anything else (or a video that
  # can't be looked up) is left for yt-dlp
  defp youtube_play_type(url) do
    with video_id when is_binary(video_id) <- Services.Youtube.get_video_id_from_url(url),
         {:ok, %{liveStreamingDetails: details}} when not is_nil(details) <-
           Services.Youtube.get_video(video_id) do
      :stream
    else
      _ -> :ytdl
    end
  end
end
