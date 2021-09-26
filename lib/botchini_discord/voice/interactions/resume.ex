defmodule BotchiniDiscord.Voice.Interactions.Resume do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /resume slash command
  """

  alias Botchini.{Discord, Voice}
  alias BotchiniDiscord.Voice.Responses.Components

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

      if !Nostrum.Voice.playing?(interaction.guild_id) do
        Nostrum.Voice.resume(interaction.guild_id)
      end

      %{
        type: 4,
        data: %{
          content: "Resuming current song",
          components: [Components.pause_controls()]
        }
      }
    else
      %{
        type: 4,
        data: %{content: "No song in queue"}
      }
    end
  end
end
