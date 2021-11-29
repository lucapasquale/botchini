defmodule BotchiniDiscord.Twitch.Interactions.ConfirmUnfollow do
  @moduledoc """
  Handles the confirmation before unfollowing a stream
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Twitch
  alias BotchiniDiscord.Twitch.Responses.Components
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}

  @behaviour InteractionBehaviour

  @impl InteractionBehaviour
  @spec get_command() :: nil
  def get_command, do: nil

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    {type, _} = Helpers.get_option(options, "type")
    {stream_code, _} = Helpers.get_option(options, "stream")
    stream_code = Helpers.cleanup_stream_code(stream_code)

    confirm_unfollow(interaction, type, stream_code)
  end

  defp confirm_unfollow(interaction, "ask", stream_code) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Twitch.channel_follower(stream_code, follow_info) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Not following #{stream_code}"}
        }

      {:ok, _} ->
        %{
          type: 4,
          data: %{
            content: unfollow_message(interaction, stream_code),
            components: [Components.confirm_unfollow_stream(stream_code)]
          }
        }
    end
  end

  defp confirm_unfollow(interaction, "cancel", stream_code) do
    %{
      type: 7,
      data: %{
        content: """
        #{unfollow_message(interaction, stream_code)}
        - Canceled unfollowing
        """,
        components: []
      }
    }
  end

  defp confirm_unfollow(interaction, "confirm", stream_code) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Twitch.unfollow(stream_code, follow_info) do
      {:error, :not_found} ->
        %{
          type: 7,
          data: %{
            content: """
            #{unfollow_message(interaction, stream_code)}
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
            #{unfollow_message(interaction, stream_code)}
            - Stream unfollowed
            """,
            components: []
          }
        }
    end
  end

  defp unfollow_message(interaction, stream_code) do
    if is_nil(interaction.member) do
      "Are you sure you want to unfollow **#{stream_code}**?"
    else
      "<@#{interaction.member.user.id}> are you sure you want to unfollow **#{stream_code}**?"
    end
  end
end
