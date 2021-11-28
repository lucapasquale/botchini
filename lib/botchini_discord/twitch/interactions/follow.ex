defmodule BotchiniDiscord.Twitch.Interactions.Follow do
  @behaviour BotchiniDiscord.InteractionBehaviour

  @moduledoc """
  Handles /follow slash command
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.{Discord, Twitch}
  alias BotchiniDiscord.Twitch.Responses.{Components, Embeds}

  @impl BotchiniDiscord.InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "follow",
      description: "Start following twitch streams",
      options: [
        %{
          type: 3,
          name: "stream",
          description: "Twitch stream code",
          required: true
        }
      ]
    }

  @impl BotchiniDiscord.InteractionBehaviour
  @spec handle_interaction(Interaction.t(), %{stream_code: String.t()}) :: map()
  def handle_interaction(interaction, %{stream_code: stream_code}) do
    guild = get_guild(interaction)

    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id),
      user_id: interaction.member && Integer.to_string(interaction.member.user.id)
    }

    case Twitch.follow_stream(BotchiniDiscord.Twitch.format_code(stream_code), guild, follow_info) do
      {:error, :invalid_stream} ->
        %{
          type: 4,
          data: %{content: "Twitch stream **#{stream_code}** not found!"}
        }

      {:error, :already_following} ->
        %{
          type: 4,
          data: %{content: "Already following!"}
        }

      {:ok, stream} ->
        spawn(fn ->
          # Waits for the slash command response so it shows message after it
          :timer.sleep(200)
          send_stream_online_message(interaction.channel_id, stream)
        end)

        %{
          type: 4,
          data: %{content: "Following the stream **#{stream.code}**!"}
        }
    end
  end

  defp get_guild(interaction) do
    if is_nil(interaction.guild_id) do
      nil
    else
      {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))
      guild
    end
  end

  defp send_stream_online_message(channel_id, stream) do
    {:ok, {user_data, stream_data}} = Twitch.stream_info(stream.code)

    if stream_data != nil do
      Nostrum.Api.create_message(
        channel_id,
        embed: Embeds.stream_online(user_data, stream_data),
        components: [Components.unfollow_stream(stream.code)]
      )
    end
  end
end
