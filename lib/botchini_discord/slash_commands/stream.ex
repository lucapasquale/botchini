defmodule BotchiniDiscord.SlashCommands.Stream do
  @moduledoc """
  Handles slash commands for twitch streams
  """

  alias Botchini.Domain
  alias Botchini.Schema.Guild
  alias Botchini.Twitch.API
  alias BotchiniDiscord.Messages.StreamOnline
  import BotchiniDiscord.SlashCommands

  @spec follow(Nostrum.Struct.Interaction.t(), String.t()) :: no_return()
  def follow(interaction, stream_code) do
    guild = Guild.find(Integer.to_string(interaction.guild_id))

    if is_nil(guild) do
      raise("Discord server not found!")
    end

    response =
      Domain.Stream.follow(stream_code, %{
        guild: guild,
        channel_id: Integer.to_string(interaction.channel_id),
        user_id: Integer.to_string(interaction.member.user.id)
      })

    case response do
      {:error, :invalid_stream} ->
        respond_interaction(interaction, "Invalid Twitch stream!")

      {:error, :already_following} ->
        respond_interaction(interaction, "Already following!")

      {:ok, stream} ->
        respond_interaction(interaction, "Following the stream #{stream.code}!")

        case API.get_stream(stream.code) do
          nil ->
            :noop

          stream_data ->
            user_data = API.get_user(stream.code)

            StreamOnline.send_message(
              interaction.channel_id,
              {user_data, stream_data}
            )
        end
    end
  end

  @spec unfollow(Nostrum.Struct.Interaction.t(), String.t()) :: no_return()
  def unfollow(interaction, stream_code) do
    case Domain.Stream.stop_following(stream_code, Integer.to_string(interaction.channel_id)) do
      {:error, :not_found} ->
        respond_interaction(
          interaction,
          "Stream #{stream_code} was not being followed"
        )

      {:ok} ->
        respond_interaction(
          interaction,
          "Removed #{stream_code} from your following streams"
        )
    end
  end

  @spec list(Nostrum.Struct.Interaction.t()) :: no_return()
  def list(interaction) do
    case Domain.Stream.following_list(Integer.to_string(interaction.channel_id)) do
      {:ok, []} ->
        respond_interaction(interaction, "Not following any stream!")

      {:ok, streams} ->
        stream_codes = Enum.map(streams, fn stream -> stream.code end)

        respond_interaction(
          interaction,
          "**Following streams:**\n" <> Enum.join(stream_codes, "\n")
        )
    end
  end

  @spec get_commands() :: [map()]
  def get_commands do
    [
      %{
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
      },
      %{
        name: "unfollow",
        description: "Stop following twitch stream",
        options: [
          %{
            type: 3,
            name: "stream",
            description: "twitch stream code",
            required: true
          }
        ]
      },
      %{
        name: "following",
        description: "list streams"
      }
    ]
  end
end
