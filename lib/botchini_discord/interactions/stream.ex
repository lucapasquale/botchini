defmodule BotchiniDiscord.Interactions.Stream do
  @moduledoc """
  Handles /stream slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Twitch
  alias BotchiniDiscord.Responses.{Components, Embeds}

  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "stream",
      description: "Information about a twitch user",
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
  def handle_interaction(_interaction, stream_code) do
    case Twitch.stream_info(stream_code) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Invalid Twitch stream!"}
        }

      {:ok, {user, _}} ->
        %{
          type: 4,
          data: %{
            embeds: [Embeds.twitch_user(user)],
            components: [Components.follow_stream(stream_code)]
          }
        }
    end
  end
end
