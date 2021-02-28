defmodule Botchini.Consumer do
  require Logger
  use Nostrum.Consumer

  alias Botchini.Commands

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _data, _ws_state}) do
    Logger.info("Bot started!")
    Botchini.Crons.Twitch.sync_streams()
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case parse_msg_content(msg) do
      ["!ping"] -> Commands.Basic.ping(msg)
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
