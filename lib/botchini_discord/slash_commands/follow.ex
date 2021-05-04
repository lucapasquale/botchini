defmodule BotchiniDiscord.SlashCommands.Follow do
  @moduledoc """
  Handles /follow slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.{Discord, Twitch}
  alias BotchiniDiscord.Messages

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
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))

    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id),
      user_id: Integer.to_string(interaction.member.user.id)
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

  defp format_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end

  defp send_stream_online_message(channel_id, stream) do
    {:ok, {user, stream_data}} = Twitch.stream_info(stream.code)

    if stream_data != nil do
      Messages.StreamOnline.send_message(channel_id, {user, stream_data})
    end
  end
end
