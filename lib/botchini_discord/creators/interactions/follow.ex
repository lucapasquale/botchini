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
          name: "term",
          required: true,
          description: "Twitch stream or YouTube channel"
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    case Enum.find(options, fn opt -> opt.name == "creator_id" end) do
      nil ->
        service = Helpers.get_service(options)
        {term, _autocomplete} = Helpers.get_option(options, "term")

        follow_by_term(interaction, {service, term})

      creator_id_option ->
        creator_id = creator_id_option.value
        follow_by_creator_id(interaction, creator_id)
    end
  end

  defp follow_by_term(interaction, {service, term}) do
    case Creators.upsert(service, term) do
      {:error, _} ->
        %{
          type: 4,
          data: %{content: "Creator not found!"}
        }

      {:ok, creator} ->
        follow_stream(interaction, creator)
    end
  end

  defp follow_by_creator_id(interaction, creator_id) do
    case Creators.creator_by_id(creator_id) do
      nil ->
        %{
          type: 4,
          data: %{content: "Creator not found!"}
        }

      creator ->
        follow_stream(interaction, creator)
    end
  end

  defp follow_stream(interaction, creator) do
    guild = get_guild(interaction)

    follow_info = %{
      channel_id: Integer.to_string(interaction.channel_id),
      user_id: interaction.member && Integer.to_string(interaction.member.user.id)
    }

    case Creators.follow(creator, guild, follow_info) do
      {:error, :already_following} ->
        %{
          type: 4,
          data: %{content: "Already following!"}
        }

      {:ok, _} ->
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
