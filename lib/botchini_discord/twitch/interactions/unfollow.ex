defmodule BotchiniDiscord.Twitch.Interactions.Unfollow do
  @behaviour BotchiniDiscord.InteractionBehaviour

  @moduledoc """
  Handles /unfollow slash command
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.Twitch

  @impl BotchiniDiscord.InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "unfollow",
      description: "Stop following twitch stream",
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
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Twitch.unfollow(format_code(stream_code), follow_info) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Stream #{stream_code} was not being followed"}
        }

      {:ok} ->
        %{
          type: 4,
          data: %{content: "Removed #{stream_code} from your following streams"}
        }
    end
  end

  defp format_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end
end
