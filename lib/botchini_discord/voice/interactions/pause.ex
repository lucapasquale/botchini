defmodule BotchiniDiscord.Voice.Interactions.Pause do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /pause slash command
  """

  alias Botchini.{Discord, Voice}

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "pause",
      description: "Pause current song"
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

    if Nostrum.Voice.playing?(interaction.guild_id) do
      Voice.pause(guild)
      Nostrum.Voice.pause(interaction.guild_id)

      %{
        type: 4,
        data: %{content: "Paused current song"}
      }
    else
      %{
        type: 4,
        data: %{content: "Not currently playing"}
      }
    end
  end
end
