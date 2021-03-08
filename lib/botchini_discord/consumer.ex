defmodule BotchiniDiscord.Consumer do
  @moduledoc """
  Consumes events from the Discord API connection
  """

  require Logger
  use Nostrum.Consumer

  alias BotchiniDiscord.Commands

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _data, _ws_state}) do
    Logger.info("Bot started!")
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case parse_msg_content(msg) do
      ["!ping"] -> Commands.Basic.ping(msg)
      ["!status"] -> Commands.Basic.status(msg)
      ["!stream", "list"] -> Commands.Stream.list(msg)
      ["!stream", "add", stream_code] -> Commands.Stream.add(msg, stream_code)
      ["!stream", "remove", stream_code] -> Commands.Stream.remove(msg, stream_code)
      _ -> :ignore
    end
  end

  def handle_event(_event) do
    :noop
  end

  defp parse_msg_content(msg) do
    msg.content
    |> String.trim()
    |> String.split(" ")
  end
end
