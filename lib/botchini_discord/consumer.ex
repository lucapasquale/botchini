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

    version = to_string(Application.spec(:botchini, :vsn))
    Nostrum.Api.update_status(:online, "on v#{version}")

    Logger.info("Bot started!")
  end

  def handle_event({:GUILD_CREATE, {guild}, _ws_state}) do
    IO.puts("CHEGOU EVENTO")
    discord_guild_id = Integer.to_string(guild.id)

    case Guild.find(discord_guild_id) do
      nil ->
        Guild.insert(%Guild{discord_guild_id: discord_guild_id})
        Logger.info("Added new guild", discord_guild_id: discord_guild_id)

      _ ->
        :noop
    end
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    SlashCommands.handle_interaction(interaction)
  end

  def handle_event(_event) do
    :noop
  end
end
