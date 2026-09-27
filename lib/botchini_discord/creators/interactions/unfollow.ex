defmodule BotchiniDiscord.Creators.Interactions.Unfollow do
  @moduledoc """
  Handles /unfollow slash command
  """

  alias Nostrum.Constants.{ApplicationCommandOptionType, InteractionCallbackType}
  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.Creators
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
          type: ApplicationCommandOptionType.string(),
          name: "service",
          required: true,
          description: "Service the creator is from",
          choices: [
            %{name: "Twitch", value: "twitch"},
            %{name: "YouTube", value: "youtube"}
          ]
        },
        %{
          type: ApplicationCommandOptionType.string(),
          name: "term",
          required: true,
          autocomplete: true,
          description: "Twitch stream or YouTube channel"
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    service = Helpers.get_service(options)
    {term, is_autocomplete} = Helpers.get_option(options, "term")

    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    if is_autocomplete do
      search_creators_to_unfollow({service, term}, follow_info)
    else
      unfollow_stream({service, term}, follow_info)
    end
  end

  defp search_creators_to_unfollow({service, term}, follow_info) do
    choices =
      Creators.search_following_creators({service, term}, follow_info)
      |> Enum.map(fn {id, name} -> %{name: name, value: Integer.to_string(id)} end)

    %{
      type: InteractionCallbackType.application_command_autocomplete_result(),
      data: %{choices: choices}
    }
  end

  # On submit the term holds the creator id of the picked suggestion, or
  # free text if the user submitted without picking one
  defp unfollow_stream({_service, creator_id}, follow_info) do
    with {id, ""} <- Integer.parse(creator_id),
         {:ok, creator} <- Creators.unfollow(id, follow_info) do
      %{
        type: InteractionCallbackType.channel_message_with_source(),
        data: %{content: "Stopped following **#{creator.name}**"}
      }
    else
      _ ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Creator was not being followed!"}
        }
    end
  end
end
