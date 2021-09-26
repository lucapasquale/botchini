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
    guild = Discord.fetch_guild(Integer.to_string(interaction.guild_id))
    next_song = Voice.get_next_track(guild)

    :ok = Nostrum.Voice.stop(interaction.guild_id)

    if is_nil(next_song) do
      %{
        type: 4,
        data: %{content: "No song in queue, stopping"}
      }
    else
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
