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

      true ->
        %{
          type: 4,
          data: %{content: "Invalid command"}
        }
    end
  end

  def handle_play(interaction, options) do
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

  defp get_voice_channel_of_msg(_) do
    459_166_748_432_924_695
  end

  # defp get_voice_channel_of_msg(interaction) do
  #   interaction.guild_id
  #   |> GuildCache.get!()
  #   |> Map.get(:voice_states)
  #   |> Enum.find(%{}, fn v -> v.user_id == interaction.member.user.id end)
  #   |> Map.get(:channel_id)
  # end

  defp get_track_url(url) do
    if String.starts_with?(url, "http") do
      url
    else
      "ytsearch:#{url}"
    end
  end
end
