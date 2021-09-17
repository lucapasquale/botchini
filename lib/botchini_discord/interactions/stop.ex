defmodule BotchiniDiscord.Interactions.Stop do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /play slash command
  """

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "stop",
      description: "Information about the bot"
    }

  @impl BotchiniDiscord.Interaction
  @spec handle_interaction(Interaction.t(), map()) :: map()
  def handle_interaction(interaction, _payload) do
    Nostrum.Voice.stop(interaction.guild_id)
    Nostrum.Voice.leave_channel(interaction.guild_id)

    %{
      type: 4,
      data: %{content: "left channel"}
    }
  end
end
