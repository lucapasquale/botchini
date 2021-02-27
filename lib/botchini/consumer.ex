defmodule Botchini.Consumer do
  require Logger
  use Nostrum.Consumer

  alias Botchini.Commands

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _data, _ws_state}) do
    Logger.info("Bot started!")
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    args = msg.content
    |> String.trim
    |> String.split(" ")

    case args do
      ["!ping"] -> Commands.Basic.ping(msg)
      ["!stream" | args] -> Commands.Stream.consume(msg, args)

      _ -> :ignore
    end
  end

  def handle_event(_event) do
    :noop
  end
end
