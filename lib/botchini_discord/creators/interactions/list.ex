defmodule BotchiniDiscord.Creators.Interactions.List do
  @moduledoc """
  Handles /list slash command
  """

  alias Nostrum.Cache.ChannelCache
  alias Nostrum.Constants.InteractionCallbackType
  alias Nostrum.Struct.{ApplicationCommand, Embed, Interaction}

  alias Botchini.{Creators, Discord}
  alias BotchiniDiscord.InteractionBehaviour

  @behaviour InteractionBehaviour

  @impl InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "list",
      description: "List followed streams by channel"
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, _options) when is_nil(interaction.guild_id) do
    case Creators.channel_following_list(Integer.to_string(interaction.channel_id)) do
      {:ok, following} when following == [] ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Not following any stream!"}
        }

      {:ok, following} ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Following streams:\n#{Enum.join(following, "\n")}"}
        }
    end
  end

  def handle_interaction(interaction, _options) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))

    case Creators.guild_following_list(guild) do
      {:ok, following} when following == [] ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{content: "Not following any stream!"}
        }

      {:ok, following} ->
        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{embeds: [guild_following_embed(following)]}
        }
    end
  end

  defp guild_following_embed(following) do
    channel_groups = Enum.group_by(following, fn {channel_id, _} -> channel_id end)

    fields =
      channel_groups
      |> Enum.reduce([], fn {channel_id, following}, acc ->
        {:ok, channel} = ChannelCache.get(String.to_integer(channel_id))
        stream_codes = Enum.map(following, &elem(&1, 1))

        acc ++
          [
            %Embed.Field{
              name: "#" <> channel.name,
              value: Enum.join(stream_codes, "\n"),
              inline: true
            }
          ]
      end)

    %Embed{title: "Following streams", fields: fields}
  end
end
