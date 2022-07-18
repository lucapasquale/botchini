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
          name: "service",
          required: true,
          description: "Service the creator is from",
          choices: [
            %{name: "Twitch", value: "twitch"},
            %{name: "YouTube", value: "youtube"}
          ]
        },
        %{
          type: 3,
          name: "term",
          required: true,
          description: "Twitch stream or YouTube channel"
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(_interaction, options) do
    service = Helpers.get_service(options)
    {term, _autocomplete} = Helpers.get_option(options, "term")

    case Creators.upsert(service, term) do
      {:error, _} ->
        %{
          type: 4,
          data: %{content: "Creator not found!"}
        }

      {:ok, creator} ->
        %{
          type: 4,
          data: %{
            embeds: [Embeds.creator_embed(creator)],
            components: [Components.follow_creator(creator.id)]
          }
        }
    end
  end
end
