defmodule BotchiniDiscord.Interactions.Play do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /play slash command
  """

  alias Botchini.{Discord, Voice}

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "play",
      description: "Information about the bot",
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
      data: %{content: "Cannot play from outside of a guild!"}
    }
  end

  def handle_interaction(interaction, %{url: url}) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))

    case Nostrum.Voice.get_channel_id(interaction.guild_id) do
      nil ->
        case get_voice_channel_of_msg(interaction) do
          nil ->
            %{
              type: 4,
              data: %{content: "Please enter a voice channel first!"}
            }

          channel_id ->
            Voice.insert_track(url, guild)
            Nostrum.Voice.join_channel(interaction.guild_id, channel_id)

            %{
              type: 4,
              data: %{content: "playing"}
            }
        end

      _channel_id ->
        Voice.insert_track(url, guild)

        %{
          type: 4,
          data: %{content: "playing2"}
        }
    end
  end

  defp get_voice_channel_of_msg(interaction) do
    interaction.guild_id
    |> Nostrum.Cache.GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(%{}, fn v -> v.user_id == interaction.member.user.id end)
    |> Map.get(:channel_id)
  end
end
