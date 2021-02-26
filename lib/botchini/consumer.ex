defmodule Botchini.Consumer do
  use Nostrum.Consumer

  alias Botchini.Commands

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case String.split(msg.content, " ") do
      ["!ping"] -> Commands.Basic.ping(msg)

      ["!stream", "add" | args] -> Commands.Stream.add(msg, args)
      ["!stream", "remove" | args] -> Commands.Stream.remove(msg, args)

      _ -> :ignore
    end
  end

  def handle_event(_event) do
    :noop
  end
end
