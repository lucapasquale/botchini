defmodule BotchiniDiscord.Voice.Interactions.Resume do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /resume slash command
  """

  alias Botchini.{Discord, Voice}
  alias BotchiniDiscord.Voice.Responses.Components

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map() | nil
  def get_command, do: nil
  # _TODO: fix resume
  # def get_command,
  #   do: %{
  #     name: "resume",
  #     description: "Resumes current song"
  #   }

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
    cur_track = Voice.get_current_track(guild)

    if is_nil(cur_track) || cur_track.status != :paused do
      %{
        type: 4,
        data: %{content: "No song to resume!"}
      }
    else
      Voice.resume(guild)
      :ok = Nostrum.Voice.resume(interaction.guild_id)

      %{
        type: 4,
        data: %{
          content: "Resuming current song",
          components: [Components.pause_controls()]
        }
      }
    end
  end
end
