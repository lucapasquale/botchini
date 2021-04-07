defmodule BotchiniDiscord.Consumer do
  @moduledoc """
  Consumes events from the Discord API connection
  """

  require Logger
  use Nostrum.Consumer

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _data, _ws_state}) do
    BotchiniDiscord.SlashCommands.assign_commands()
    Logger.info("Bot started!")
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    BotchiniDiscord.SlashCommands.handle_interaction(interaction)
  end

  def handle_event(_event) do
    :noop
  end
end
