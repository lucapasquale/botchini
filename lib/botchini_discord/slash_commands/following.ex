defmodule BotchiniDiscord.SlashCommands.Following do
  @moduledoc """
  Handles /following slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Domain.Stream

  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "following",
      description: "list streams"
    }

  @spec handle_interaction(Interaction.t()) :: no_return()
  def handle_interaction(interaction) do
    case Stream.following_list(Integer.to_string(interaction.channel_id)) do
      {:ok, []} ->
        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "Not following any stream!"}
        })

      {:ok, streams} ->
        stream_codes = Enum.map(streams, fn stream -> stream.code end)

        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "**Following streams:**\n" <> Enum.join(stream_codes, "\n")}
        })
    end
  end
end
