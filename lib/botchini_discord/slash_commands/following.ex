defmodule BotchiniDiscord.SlashCommands.Following do
  @moduledoc """
  Handles /following slash command
  """

  alias Nostrum.Cache.ChannelCache
  alias Nostrum.Struct.{Embed, Interaction}

  alias Botchini.{Discord, Twitch}

  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "following",
      description: "List followed streams by channel"
    }

  @spec handle_interaction(Interaction.t()) :: map()
  def handle_interaction(interaction) when is_nil(interaction.guild_id) do
    case Twitch.channel_following_list(Integer.to_string(interaction.channel_id)) do
      {:ok, following} when following == [] ->
        %{content: "Not following any stream!"}

      {:ok, following} ->
        %{content: "Following streams:\n#{Enum.join(following, "\n")}"}
    end
  end

  def handle_interaction(interaction) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))

    case Twitch.guild_following_list(guild) do
      {:ok, following} when following == [] ->
        %{content: "Not following any stream!"}

      {:ok, following} ->
        %{embeds: [guild_following_embed(following)]}
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
