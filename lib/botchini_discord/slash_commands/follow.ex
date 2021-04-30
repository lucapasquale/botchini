defmodule BotchiniDiscord.SlashCommands.Follow do
  @moduledoc """
  Handles /follow slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Discord
  alias Botchini.Twitch
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
          description: "twitch stream code",
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
        case Twitch.API.get_stream(stream.code) do
          nil ->
            :noop

          stream_data ->
            user_data = Twitch.API.get_user(stream.code)

            Messages.StreamOnline.send_message(
              interaction.channel_id,
              {user_data, stream_data}
            )
        end

        %{content: "Following the stream #{stream.code}!"}
    end
  end

  defp format_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end
end
