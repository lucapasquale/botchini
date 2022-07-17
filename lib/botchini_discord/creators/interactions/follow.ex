defmodule BotchiniDiscord.Creators.Interactions.Follow do
  @moduledoc """
  Handles /follow slash command
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.{Creators, Discord}
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}

  @behaviour InteractionBehaviour

  @impl InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "follow",
      description: "Start following twitch streams",
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
          description: "Twitch code or YouTube channel"
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    service = Helpers.get_service(options)
    {code, _autocomplete} = Helpers.get_code(options)

    follow_stream(interaction, {service, code})
  end

  defp follow_stream(interaction, {service, code}) do
    guild = get_guild(interaction)

    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id),
      user_id: interaction.member && Integer.to_string(interaction.member.user.id)
    }

    case Creators.follow_creator({service, code}, guild, follow_info) do
      {:error, :invalid_creator} ->
        %{
          type: 4,
          data: %{content: "Couldn't find **#{code}**!"}
        }

      {:error, :already_following} ->
        %{
          type: 4,
          data: %{content: "Already following!"}
        }

      {:ok, creator} ->
        %{
          type: 4,
          data: %{content: "Following **#{creator.name}**!"}
        }
    end
  end

  defp get_guild(interaction) do
    if is_nil(interaction.guild_id) do
      nil
    else
      {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))
      guild
    end
  end
end
