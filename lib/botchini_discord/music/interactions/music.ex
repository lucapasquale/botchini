defmodule BotchiniDiscord.Music.Interactions.Music do
  @moduledoc """
  Handles /music slash command
  """

  alias Nostrum.Cache.GuildCache
  alias Nostrum.Constants.{ApplicationCommandOptionType, InteractionCallbackType}
  alias Nostrum.Struct.ApplicationCommand

  alias Botchini.{Discord, Music, Services}
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}
  alias BotchiniDiscord.Music.Responses.Components

  @behaviour InteractionBehaviour

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
            play_type: get_play_type_from_term(term)
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

        %{
          type: InteractionCallbackType.update_message(),
          data: %{
            content: "Paused **#{cur_track.title}**",
            components: [Components.resume_controls()]
          }
        }
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

      %{
        type: InteractionCallbackType.update_message(),
        data: %{
          content: "Resuming **#{cur_track.title}**",
          components: [Components.pause_controls()]
        }
      }
    end
  end

  defp handle_skip(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    case Music.get_next_track(guild) do
      nil ->
        Music.clear_queue(guild)
        Nostrum.Voice.stop(interaction.guild_id)

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "No song in queue, stopping"}
        }

      track ->
        Nostrum.Voice.stop(interaction.guild_id)

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

      Regex.match?(
        ~r/^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*/,
        term
      ) ->
        video_id = Services.Youtube.get_video_id_from_url(term)
        yt_video = Services.Youtube.get_video(video_id)

        if is_nil(yt_video.liveStreamingDetails) do
          :ytdl
        else
          :stream
        end

      true ->
        :ytdl
    end
  end
end
