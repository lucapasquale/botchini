defmodule BotchiniDiscord.Consumer do
  @moduledoc """
  Consumes events from the Discord API connection
  """

  require Logger
  use Nostrum.Consumer

  alias Botchini.Schema.Guild
  alias BotchiniDiscord.SlashCommands

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _data, _ws_state}) do
    SlashCommands.register_commands()
    Logger.info("Bot started!")
  end

  def handle_event({:GUILD_CREATE, {guild}, _ws_state}) do
    discord_guild_id = Integer.to_string(guild.id)

    case Guild.find(discord_guild_id) do
      nil -> Guild.insert(%Guild{discord_guild_id: discord_guild_id})
      _ -> :noop
    end
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    if is_nil(interaction.member) do
      Nostrum.Api.create_interaction_response(interaction, %{
        type: 4,
        data: %{content: "Can't use commands from DMs!"}
      })
    else
      SlashCommands.handle_interaction(interaction)
    end
  end

  def handle_event(_event) do
    :noop
  end
end
