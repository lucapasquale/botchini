defmodule BotchiniDiscord.SlashCommands.Unfollow do
  @moduledoc """
  Handles /unfollow slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Twitch

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

  @spec handle_interaction(Interaction.t(), String.t()) :: map()
  def handle_interaction(interaction, stream_code) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Twitch.unfollow(format_code(stream_code), follow_info) do
      {:error, :not_found} ->
        %{content: "Stream #{stream_code} was not being followed"}

      {:ok} ->
        %{content: "Removed #{stream_code} from your following streams"}
    end
  end

  defp format_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end
end
