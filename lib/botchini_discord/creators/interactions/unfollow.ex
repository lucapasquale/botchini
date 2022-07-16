defmodule BotchiniDiscord.Creators.Interactions.Unfollow do
  @moduledoc """
  Handles /unfollow slash command
  """

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
          type: 3,
          name: "stream",
          description: "Twitch stream code",
          required: true,
          autocomplete: true
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    {stream_code, is_autocomplete} = Helpers.get_option(options, "stream")
    stream_code = Helpers.cleanup_stream_code(stream_code)

    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    if is_autocomplete do
      search_creators_to_unfollow(stream_code, follow_info)
    else
      unfollow_stream(stream_code, follow_info)
    end
  end

  defp search_creators_to_unfollow(term, follow_info) do
    choices =
      Creators.search_following_creators(term, follow_info)
      |> Enum.map(fn stream ->
        %{name: stream.name, value: stream.code}
      end)

    %{
      type: 8,
      data: %{choices: choices}
    }
  end

  defp unfollow_stream(stream_code, follow_info) do
    case Creators.unfollow({:twitch, stream_code}, follow_info) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "Stream **#{stream_code}** was not being followed"}
        }

      {:ok} ->
        %{
          type: 4,
          data: %{content: "Removed **#{stream_code}** from your following streams"}
        }
    end
  end
end
