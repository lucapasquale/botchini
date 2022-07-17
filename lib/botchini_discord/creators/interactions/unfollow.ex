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
          name: "code",
          required: true,
          autocomplete: true,
          description: "Twitch code or YouTube channel"
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    service = Helpers.get_service(options)
    {code, is_autocomplete} = Helpers.get_code(options)

    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id)
    }

    if is_autocomplete do
      search_creators_to_unfollow({service, code}, follow_info)
    else
      unfollow_stream({service, code}, follow_info)
    end
  end

  defp search_creators_to_unfollow({service, term}, follow_info) do
    choices =
      Creators.search_following_creators({service, term}, follow_info)
      |> Enum.map(fn stream ->
        %{name: stream.name, value: stream.code}
      end)

    %{
      type: 8,
      data: %{choices: choices}
    }
  end

  defp unfollow_stream({service, code}, follow_info) do
    case Creators.unfollow({service, code}, follow_info) do
      {:error, :not_found} ->
        %{
          type: 4,
          data: %{content: "**#{code}** was not being followed"}
        }

      {:ok} ->
        %{
          type: 4,
          data: %{content: "Stopped following **#{code}**"}
        }
    end
  end
end
