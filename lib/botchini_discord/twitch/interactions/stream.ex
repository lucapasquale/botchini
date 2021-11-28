defmodule BotchiniDiscord.Twitch.Interactions.Stream do
  @behaviour BotchiniDiscord.InteractionBehaviour

  @moduledoc """
  Handles /stream slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Twitch
  alias BotchiniDiscord.Twitch.Responses.{Components, Embeds}

  @impl BotchiniDiscord.InteractionBehaviour
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

  @impl BotchiniDiscord.InteractionBehaviour
  @spec handle_interaction(Interaction.t(), %{stream_code: String.t()}) :: map()
  def handle_interaction(_interaction, %{stream_code: stream_code}) do
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
