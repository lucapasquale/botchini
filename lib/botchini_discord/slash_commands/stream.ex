defmodule BotchiniDiscord.SlashCommands.Stream do
  @moduledoc """
  Handles /stream slash command
  """

  alias Nostrum.Struct.Interaction

  alias Botchini.Twitch
  alias BotchiniDiscord.Messages.{StreamOnline, TwitchUser}

  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "stream",
      description: "Information about a twitch user",
      options: [
        %{
          type: 3,
          name: "stream",
          description: "Twitch stream code",
          required: true
        }
      ]
    }

  @spec handle_interaction(Interaction.t(), String.t()) :: map()
  def handle_interaction(_interaction, stream_code) do
    case Twitch.stream_info(stream_code) do
      {:error, :not_found} ->
        %{content: "Invalid Twitch stream!"}

      {:ok, {user, nil}} ->
        %{embeds: [TwitchUser.generate_embed(user)]}

      {:ok, {user, stream}} ->
        %{embeds: [StreamOnline.generate_embed(user, stream)]}
    end
  end
end
