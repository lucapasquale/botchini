defmodule BotchiniDiscord.Voice.Interactions.Stop do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /stop slash command
  """
  alias Botchini.{Discord, Voice}

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "stop",
      description: "Stop playing and clears queue"
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
    Voice.clear_queue(guild)

    Nostrum.Voice.stop(interaction.guild_id)

    %{
      type: 4,
      data: %{content: "Stopped playing"}
    }
  end
end
