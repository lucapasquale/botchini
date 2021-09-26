defmodule BotchiniDiscord.Voice.Interactions.Skip do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /skip slash command
  """

  alias Botchini.{Discord, Voice}
  alias BotchiniDiscord.Voice.Responses.Components

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "skip",
      description: "Skips current song"
    }

  @impl BotchiniDiscord.Interaction
  @spec handle_interaction(Interaction.t(), map()) :: map()
  def handle_interaction(interaction, _payload) when is_nil(interaction.guild_id) do
    %{
      type: 4,
      data: %{content: "Cannot use this command from outside a guild!"}
    }
  end

  def handle_interaction(interaction, _payload) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))

    Voice.pause(guild)
    Nostrum.Voice.pause(interaction.guild_id)

    case Voice.start_next_track(guild) do
      nil ->
        %{
          type: 4,
          data: %{content: "No next song in queue"}
        }

      track ->
        IO.inspect(track)
        Nostrum.Voice.play(interaction.guild_id, track.play_url, :ytdl)

        %{
          type: 4,
          data: %{
            content: "Skipping to next song",
            components: [Components.pause_controls()]
          }
        }
    end
  end
end
