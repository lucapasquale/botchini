defmodule BotchiniDiscord.Creators.Interactions.Info do
  @moduledoc """
  Handles /info slash command
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.Creators
  alias BotchiniDiscord.Creators.Responses.{Components, Embeds}
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}

  @behaviour InteractionBehaviour

  @impl InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "info",
      description: "Information about a creator",
      options: [
        %{
          type: 3,
          required: true,
          name: "service",
          description: "Service the creator is from",
          choices: [
            %{name: "Twitch", value: "twitch"},
            %{name: "YouTube", value: "youtube"}
          ]
        },
        %{
          type: 3,
          required: true,
          name: "code",
          description: "Twitch code or YouTube channel"
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(_interaction, options) do
    service = Helpers.get_service(options)
    {code, _autocomplete} = Helpers.get_code(options)

    get_stream_info({service, code})
  end

  defp get_stream_info({:twitch, code}) do
    case Creators.stream_info(code) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Creator **#{code}** not found!"}
        }

      {:ok, {user, _}} ->
        %{
          type: 4,
          data: %{
            embeds: [Embeds.twitch_user(user)],
            components: [Components.follow_stream(code)]
          }
        }
    end
  end

  defp get_stream_info({:youtube, code}) do
    case Creators.youtube_channel_info(code) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Channel **#{code}** not found!"}
        }

      {:ok, channel} ->
        %{
          type: 4,
          data: %{
            embeds: [Embeds.youtube_channel(channel)]
            # components: [Components.follow_stream(code)]
          }
        }
    end
  end
end
