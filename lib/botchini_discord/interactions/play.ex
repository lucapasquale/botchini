defmodule BotchiniDiscord.Interactions.Play do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /play slash command
  """

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "play",
      description: "Information about the bot",
      options: [
        %{
          type: 3,
          name: "url",
          description: "url to play",
          required: true
        }
      ]
    }

  @impl BotchiniDiscord.Interaction
  @spec handle_interaction(Interaction.t(), %{url: String.t()}) :: map()
  def handle_interaction(interaction, %{url: url}) do
    Nostrum.Voice.join_channel(
      interaction.guild_id,
      459_166_748_432_924_695
    )

    # try_play(interaction.guild_id, url, :ytdl)

    %{
      type: 4,
      data: %{content: "playing"}
    }
  end

  defp get_voice_channel_of_msg(interaction) do
    interaction.guild_id
    |> Nostrum.Cache.GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(%{}, fn v -> v.user_id == interaction.member.user.id end)
    |> Map.get(:channel_id)
  end

  defp try_play(guild_id, url, type, count \\ 0) do
    if count > 5 do
      :noop
    else
      case Nostrum.Voice.play(guild_id, url, type) do
        {:error, msg} ->
          IO.inspect(msg)
          Process.sleep(100)
          try_play(guild_id, url, type, count + 1)

        _ ->
          :ok
      end
    end
  end
end
