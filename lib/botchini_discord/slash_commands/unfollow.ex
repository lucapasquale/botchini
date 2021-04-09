defmodule BotchiniDiscord.SlashCommands.Unfollow do
  @moduledoc """
  Handles /unfollow slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Domain.Stream

  @spec get_command() :: map()
  def get_command,
    do: %{
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
    }

  @spec handle_interaction(Interaction.t(), String.t()) :: no_return()
  def handle_interaction(interaction, stream_code) do
    case Stream.stop_following(stream_code, Integer.to_string(interaction.channel_id)) do
      {:error, :not_found} ->
        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "Stream #{stream_code} was not being followed"}
        })

      {:ok} ->
        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "Removed #{stream_code} from your following streams"}
        })
    end
  end
end
