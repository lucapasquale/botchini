defmodule BotchiniDiscord.Twitch.Interactions.Stream do
  @moduledoc """
  Handles /stream slash command
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.Twitch
  alias BotchiniDiscord.Twitch.Responses.{Components, Embeds}
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}

  @behaviour InteractionBehaviour

  @impl InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
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

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(_interaction, options) do
    {stream_code, _} = Helpers.get_option(options, "stream")
    stream_code = Helpers.cleanup_stream_code(stream_code)

    case Twitch.stream_info(stream_code) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Twitch stream **#{stream_code}** not found!"}
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
