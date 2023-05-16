defmodule BotchiniDiscord.Creators.Interactions.Follow do
  @moduledoc """
  Handles /follow slash command
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}
  alias Nostrum.Constants.{ApplicationCommandOptionType, InteractionCallbackType}

  alias Botchini.{Creators, Discord, Services}
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
          description: "Twitch stream or YouTube channel"
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    case Enum.find(options, fn opt -> opt.name == "service_id" end) do
      nil ->
        follow_from_term(interaction, options)

      service_id_option ->
        service = Helpers.get_service(options)
        {:ok, creator} = Creators.upsert(service, service_id_option.value)

        follow_stream(interaction, creator)
    end
  end

  defp follow_from_term(interaction, options) do
    service = Helpers.get_service(options)
    {term, _autocomplete} = Helpers.get_option(options, "term")

    with {:ok, {service_id, _name}} <- Services.search_channel(service, term),
         {:ok, creator} <- Creators.upsert(service, service_id) do
      follow_stream(interaction, creator)
    else
      _ ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Creator not found!"}
        }
    end
  end

  defp follow_stream(interaction, creator) do
    guild = get_guild(interaction)

    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id),
      user_id: interaction.member && Integer.to_string(interaction.member.user_id)
    }

    case Creators.follow(creator, guild, follow_info) do
      {:error, :already_following} ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Already following!"}
        }

      {:ok, _} ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Following **#{creator.name}**!"}
        }
    end
  end

  defp get_guild(interaction) when is_nil(interaction.guild_id), do: nil

  defp get_guild(interaction) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))
    guild
  end
end
