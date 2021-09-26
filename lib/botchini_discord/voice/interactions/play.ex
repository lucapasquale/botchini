defmodule BotchiniDiscord.Voice.Interactions.Play do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /play slash command
  """

  alias Nostrum.Cache.GuildCache

  alias Botchini.{Discord, Voice}
  alias BotchiniDiscord.Voice.Responses.Components

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "play",
      description: "Play a song",
      options: [
        %{
          type: 3,
          name: "url",
          description: "url to play",
          required: true
        }
      ]
    }

  @impl BotchiniDiscord.Interaction
  @spec handle_interaction(Interaction.t(), %{url: String.t()}) :: map()
  def handle_interaction(interaction, _payload) when is_nil(interaction.guild_id) do
    %{
      type: 4,
      data: %{content: "Cannot use this command from outside a guild!"}
    }
  end

  def handle_interaction(interaction, %{url: url}) do
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))

    case get_voice_channel_of_msg(interaction) do
      nil ->
        %{
          type: 4,
          data: %{content: "Please enter a voice channel first!"}
        }

      voice_channel_id ->
        Voice.insert_track(%{play_url: get_track_url(url)}, guild)

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
