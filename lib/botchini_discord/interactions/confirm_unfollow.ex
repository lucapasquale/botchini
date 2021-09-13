defmodule BotchiniDiscord.Interactions.ConfirmUnfollow do
  @moduledoc """
  Handles /unfollow slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Twitch

  alias BotchiniDiscord.Responses.{Components}

  @spec handle_interaction(Interaction.t(), %{
          type: :ask | :cancel | :confirm,
          stream_code: String.t()
        }) ::
          map()
  def handle_interaction(_interaction, %{type: :ask, stream_code: stream_code}) do
    case Twitch.stream_info(stream_code) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Invalid Twitch stream!"}
        }

      {:ok, _} ->
        %{
          type: 4,
          data: %{
            content: "Are you sure you want to unfollow #{stream_code}?",
            components: [Components.confirm_unfollow_stream(stream_code)]
          }
        }
    end
  end

  def handle_interaction(_interaction, %{type: :cancel, stream_code: stream_code}) do
    %{
      type: 7,
      data: %{
        content: "You are still following #{stream_code}",
        components: []
      }
    }
  end

  def handle_interaction(interaction, %{type: :confirm, stream_code: stream_code}) do
    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    case Twitch.unfollow(format_code(stream_code), follow_info) do
      {:error, :not_found} ->
        %{
          type: 7,
          data: %{
            content: "Stream #{stream_code} was not being followed",
            components: []
          }
        }

      {:ok} ->
        %{
          type: 7,
          data: %{
            content: "Removed #{stream_code} from your following streams",
            components: []
          }
        }
    end
  end

  defp format_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end
end
