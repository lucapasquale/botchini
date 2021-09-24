defmodule BotchiniDiscord.Interactions.Play do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /play slash command
  """

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
  def handle_interaction(interaction, %{url: url}) do
    case get_voice_channel_of_msg(interaction) do
      nil ->
        %{
          type: 4,
          data: %{content: "Please enter a voice channel first!"}
        }

      channel_id ->
        Nostrum.Voice.join_channel(interaction.guild_id, channel_id)

        %{
          type: 4,
          data: %{content: "playing"}
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
