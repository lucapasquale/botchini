defmodule BotchiniDiscord.Twitch.Interactions.Unfollow do
  @moduledoc """
  Handles /unfollow slash command
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.Twitch
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}

  @behaviour InteractionBehaviour

  @impl InteractionBehaviour
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
          required: true,
          autocomplete: true
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    {stream_code, _} = Helpers.get_option(options, "stream")
    stream_code = Helpers.cleanup_stream_code(stream_code)

    case Twitch.unfollow(stream_code, %{channel_id: Integer.to_string(interaction.channel_id)}) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Stream **#{stream_code}** was not being followed"}
        }

      {:ok} ->
        %{
          type: 4,
          data: %{content: "Removed **#{stream_code}** from your following streams"}
        }
    end
  end
end
