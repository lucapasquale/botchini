defmodule BotchiniDiscord.Twitch.Interactions.ConfirmUnfollow do
  @behaviour BotchiniDiscord.InteractionBehaviour

  @moduledoc """
  Handles the confirmation before unfollowing a stream
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Twitch
  alias BotchiniDiscord.Twitch.Responses.Components

  @impl BotchiniDiscord.InteractionBehaviour
  @spec get_command() :: nil
  def get_command, do: nil

  @impl BotchiniDiscord.InteractionBehaviour
  @spec handle_interaction(Interaction.t(), %{
          type: :ask | :cancel | :confirm,
          stream_code: String.t()
        }) :: map()
  def handle_interaction(interaction, %{type: :ask, stream_code: stream_code}) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Twitch.channel_follower(BotchiniDiscord.Twitch.format_code(stream_code), follow_info) do
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

  def handle_interaction(interaction, %{type: :cancel, stream_code: stream_code}) do
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

  def handle_interaction(interaction, %{type: :confirm, stream_code: stream_code}) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Twitch.unfollow(BotchiniDiscord.Twitch.format_code(stream_code), follow_info) do
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
