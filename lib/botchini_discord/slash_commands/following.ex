defmodule BotchiniDiscord.SlashCommands.Following do
  @moduledoc """
  Handles /following slash command
  """

  alias Nostrum.Cache.ChannelCache
  alias Nostrum.Struct.{Embed, Interaction}

  alias Botchini.Domain.Stream

  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "following",
      description: "List streams"
    }

  @spec handle_interaction(Interaction.t()) :: map()
  def handle_interaction(interaction) do
    case Stream.following_list(Integer.to_string(interaction.guild_id)) do
      {:ok, streams} when streams == [] ->
        %{content: "Not following any stream!"}

      {:ok, streams} ->
        %{embeds: [following_streams_embed(streams)]}
    end
  end

  defp following_streams_embed(streams) do
    channel_groups = Enum.group_by(streams, fn {channel_id, _} -> channel_id end)

    fields =
      channel_groups
      |> Enum.reduce([], fn {channel_id, streams}, acc ->
        {:ok, channel} = ChannelCache.get(String.to_integer(channel_id))
        stream_codes = Enum.map(streams, &elem(&1, 1))

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
