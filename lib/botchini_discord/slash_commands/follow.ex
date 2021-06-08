defmodule BotchiniDiscord.SlashCommands.Follow do
  @moduledoc """
  Handles /follow slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.{Discord, Twitch}
  alias BotchiniDiscord.Messages.StreamOnline

  @spec get_command() :: map()
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

  @spec handle_interaction(Interaction.t(), String.t()) :: map()
  def handle_interaction(interaction, stream_code) do
    guild = get_guild(interaction)

    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id),
      user_id: interaction.member && Integer.to_string(interaction.member.user.id)
    }

    case Twitch.follow_stream(format_code(stream_code), guild, follow_info) do
      {:error, :invalid_stream} ->
        %{content: "Invalid Twitch stream!"}

      {:error, :already_following} ->
        %{content: "Already following!"}

      {:ok, stream} ->
        send_stream_online_message(interaction.channel_id, stream)
        %{content: "Following the stream #{stream.code}!"}
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

  defp format_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end

  defp send_stream_online_message(channel_id, stream) do
    {:ok, {user_data, stream_data}} = Twitch.stream_info(stream.code)

    if stream_data != nil do
      Nostrum.Api.create_message(
        channel_id,
        embed: StreamOnline.generate_embed(user_data, stream_data),
        components: [
          %{
            type: 1,
            components: [
              %{
                type: 2,
                style: 4,
                label: "Unfollow stream",
                custom_id: "unfollow:#{stream.code}"
              }
            ]
          }
        ]
      )
    end
  end
end
