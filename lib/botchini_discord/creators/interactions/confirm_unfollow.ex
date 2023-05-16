defmodule BotchiniDiscord.Creators.Interactions.ConfirmUnfollow do
  @moduledoc """
  Handles the confirmation before unfollowing a stream
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Creators
  alias BotchiniDiscord.Creators.Responses.Components
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}

  @behaviour InteractionBehaviour

  @impl InteractionBehaviour
  @spec get_command() :: nil
  def get_command, do: nil

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    service = Helpers.get_service(options)
    {service_id, _autocomplete} = Helpers.get_option(options, "service_id")

    case Creators.find_by_service(service, service_id) do
      nil ->
        %{
          type: 4,
          data: %{content: "Creator not found"}
        }

      creator ->
        {type, _} = Helpers.get_option(options, "type")
        confirm_unfollow(interaction, type, creator)
    end
  end

  defp confirm_unfollow(interaction, "ask", creator) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Creators.discord_channel_follower(creator.id, follow_info) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Not following!"}
        }

      {:ok, _} ->
        %{
          type: 4,
          data: %{
            content: unfollow_message(interaction, creator),
            components: [Components.confirm_unfollow_creator(creator.service, creator.service_id)]
          }
        }
    end
  end

  defp confirm_unfollow(interaction, "cancel", creator) do
    %{
      type: 7,
      data: %{
        content: """
        #{unfollow_message(interaction, creator)}
        - Canceled unfollowing
        """,
        components: []
      }
    }
  end

  defp confirm_unfollow(interaction, "confirm", creator) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Creators.unfollow(creator.id, follow_info) do
      {:error, :not_found} ->
        %{
          type: 7,
          data: %{
            content: """
            #{unfollow_message(interaction, creator)}
            - Stream was not being followed
            """,
            components: []
          }
        }

      {:ok, _creator} ->
        %{
          type: 7,
          data: %{
            content: """
            #{unfollow_message(interaction, creator)}
            - Unfollowed #{creator.name}
            """,
            components: []
          }
        }
    end
  end

  defp unfollow_message(interaction, creator) when is_nil(interaction.member) do
    "Are you sure you want to unfollow **#{creator.name}**?"
  end

  defp unfollow_message(interaction, creator) do
    "<@#{interaction.member.user_id}> are you sure you want to unfollow **#{creator.name}**?"
  end
end
