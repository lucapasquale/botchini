defmodule BotchiniDiscord.Voice.Interactions.Resume do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /resume slash command
  """

  alias Botchini.{Discord, Voice}

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "resume",
      description: "Resumes current song"
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

    cur_track = Voice.get_current_track(guild)

    if !is_nil(cur_track) && cur_track.status == :paused do
      Voice.resume(guild)
      Nostrum.Voice.resume(interaction.guild_id)

      %{
        type: 4,
        data: %{content: "Resuming current song"}
      }
    else
      %{
        type: 4,
        data: %{content: "No song paused"}
      }
    end
  end
end
