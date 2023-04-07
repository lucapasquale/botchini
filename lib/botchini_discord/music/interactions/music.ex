defmodule BotchiniDiscord.Music.Interactions.Music do
  @moduledoc """
  Handles /music slash command
  """

  alias Nostrum.Cache.GuildCache
  alias Nostrum.Struct.ApplicationCommand

  alias Botchini.{Discord, Music}
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
          description: "Play a music",
          type: 1,
          options: [
            %{
              type: 3,
              required: true,
              name: "url",
              description: "YouTube URL or search term"
            }
          ]
        },
        %{
          name: "pause",
          description: "Pause current song",
          type: 1
        },
        %{
          name: "resume",
          description: "Resume current song",
          type: 1
        },
        %{
          name: "skip",
          description: "Skip current song",
          type: 1
        },
        %{
          name: "stop",
          description: "Stop playing",
          type: 1
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, _options) when is_nil(interaction.guild_id) do
    %{
      type: 4,
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

      true ->
        %{
          type: 4,
          data: %{content: "Invalid command"}
        }
    end
  end

  defp handle_play(interaction, options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    case get_voice_channel_of_msg(interaction) do
      nil ->
        %{
          type: 4,
          data: %{content: "Please enter a voice channel first!"}
        }

      voice_channel_id ->
        {url, _autocomplete} = Helpers.get_option!(options, "url")
        Music.insert_track(%{play_url: get_track_url(url)}, guild)

        if Nostrum.Voice.get_channel_id(interaction.guild_id) != voice_channel_id do
          Nostrum.Voice.join_channel(interaction.guild_id, voice_channel_id)
        end

        %{
          type: 4,
          data: %{
            content: "Added #{url} to queue",
            components: [Components.pause_controls()]
          }
        }
    end
  end

  defp handle_pause(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    if Nostrum.Voice.playing?(interaction.guild_id) do
      Music.pause(guild)
      Nostrum.Voice.pause(interaction.guild_id)

      %{
        type: 4,
        data: %{
          content: "Paused current song",
          components: [Components.resume_controls()]
        }
      }
    else
      %{
        type: 4,
        data: %{content: "Not currently playing"}
      }
    end
  end

  defp handle_resume(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))
    cur_track = Music.get_current_track(guild)

    if is_nil(cur_track) || cur_track.status != :paused do
      %{
        type: 4,
        data: %{content: "No song to resume!"}
      }
    else
      Music.resume(guild)
      :ok = Nostrum.Voice.resume(interaction.guild_id)

      %{
        type: 4,
        data: %{
          content: "Resuming current song",
          components: [Components.pause_controls()]
        }
      }
    end
  end

  defp handle_stop(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    case Music.get_current_track(guild) do
      nil ->
        %{
          type: 4,
          data: %{content: "No song in queue"}
        }

      _track ->
        Music.clear_queue(guild)
        Nostrum.Voice.stop(interaction.guild_id)

        %{
          type: 4,
          data: %{content: "Stopped playing"}
        }
    end
  end

  defp handle_skip(interaction, _options) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))
    next_song = Music.get_next_track(guild)

    if is_nil(next_song) do
      Music.clear_queue(guild)
      :ok = Nostrum.Voice.stop(interaction.guild_id)

      %{
        type: 4,
        data: %{content: "No song in queue, stopping"}
      }
    else
      :ok = Nostrum.Voice.stop(interaction.guild_id)

      %{
        type: 4,
        data: %{
          content: "Skipping to next song",
          components: [Components.pause_controls()]
        }
      }
    end
  end

  defp get_voice_channel_of_msg(interaction) do
    interaction.guild_id
    |> GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(%{}, fn v -> v.user_id == interaction.member.user.id end)
    |> Map.get(:channel_id)
  end

  defp get_track_url(url) do
    if String.starts_with?(url, "http") do
      url
    else
      "ytsearch:#{url}"
    end
  end
end
