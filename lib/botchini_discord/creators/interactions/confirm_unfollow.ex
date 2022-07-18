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
    {type, _} = Helpers.get_option(options, "type")
    {creator_id, _autocomplete} = Helpers.get_option(options, "creator_id")

    confirm_unfollow(interaction, type, String.to_integer(creator_id))
  end

  defp confirm_unfollow(interaction, "ask", creator_id) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Creators.discord_channel_follower(creator_id, follow_info) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Not following!"}
        }

      {:ok, _} ->
        %{
          type: 4,
          data: %{
            content: unfollow_message(interaction, creator_id),
            components: [Components.confirm_unfollow_creator(creator_id)]
          }
        }
    end
  end

  defp confirm_unfollow(interaction, "cancel", creator_id) do
    %{
      type: 7,
      data: %{
        content: """
        #{unfollow_message(interaction, creator_id)}
        - Canceled unfollowing
        """,
        components: []
      }
    }
  end

  defp confirm_unfollow(interaction, "confirm", creator_id) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Creators.unfollow_by_creator_id(creator_id, follow_info) do
      {:error, :not_found} ->
        %{
          type: 7,
          data: %{
            content: """
            #{unfollow_message(interaction, creator_id)}
            - Stream was not being followed
            """,
            components: []
          }
        }

      {:ok} ->
        %{
          type: 7,
          data: %{
            content: """
            #{unfollow_message(interaction, creator_id)}
            - Stream unfollowed
            """,
            components: []
          }
        }
    end
  end

  defp unfollow_message(interaction, creator_id) do
    if is_nil(interaction.member) do
      "Are you sure you want to unfollow **#{creator_id}**?"
    else
      "<@#{interaction.member.user.id}> are you sure you want to unfollow **#{creator_id}**?"
    end
  end
end
