defmodule BotchiniDiscord.SlashCommands.Follow do
  @moduledoc """
  Handles /follow slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Domain
  alias Botchini.Schema.Guild
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

  @spec handle_interaction(Interaction.t(), String.t()) :: no_return()
  def handle_interaction(interaction, stream_code) do
    case follow_stream(interaction, stream_code) do
      {:error, :invalid_stream} ->
        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "Invalid Twitch stream!"}
        })

      {:error, :already_following} ->
        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "Already following!"}
        })

      {:ok, stream} ->
        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "Following the stream #{stream.code}!"}
        })

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
    end
  end

  defp follow_stream(interaction, stream_code) do
    guild = Guild.find(Integer.to_string(interaction.guild_id))

    Domain.Stream.follow(stream_code, %{
      guild: guild,
      channel_id: Integer.to_string(interaction.channel_id),
      user_id: Integer.to_string(interaction.member.user.id)
    })
  end
end
