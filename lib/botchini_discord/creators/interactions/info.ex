defmodule BotchiniDiscord.Creators.Interactions.Info do
  @moduledoc """
  Handles /info slash command
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.{Creators, Services}
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
  def handle_interaction(interaction, options) do
    service = Helpers.get_service(options)
    {term, _autocomplete} = Helpers.get_option(options, "term")

    case Services.search_channel(service, term) do
      {:error, _} ->
        %{
          type: 4,
          data: %{content: "Creator not found!"}
        }

      {:ok, {service_id, _name}} ->
        follower =
          Creators.discord_channel_follower(
            service,
            service_id,
            %{channel_id: Integer.to_string(interaction.channel_id)}
          )

        component =
          if is_nil(follower),
            do: Components.follow_creator(service, service_id),
            else: Components.unfollow_creator(service, service_id)

        %{
          type: 4,
          data: %{
            embeds: [Embeds.creator_embed(service, service_id)],
            components: [component]
          }
        }
    end
  end
end
