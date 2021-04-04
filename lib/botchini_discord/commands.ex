defmodule BotchiniDiscord.Commands do
  @moduledoc """
  Routes discord messages into commands
  """

  alias Nostrum.Struct.Message
  alias BotchiniDiscord.Commands.{Basic, Stream}

  @spec handle([String.t()], Message.t()) :: any()
  def handle(["ping"], msg), do: Basic.ping(msg)
  def handle(["status"], msg), do: Basic.status(msg)

  def handle(["stream", "list"], msg), do: Stream.list(msg)
  def handle(["stream", "add", code], msg), do: Stream.add(msg, code)
  def handle(["stream", "remove", code], msg), do: Stream.remove(msg, code)

  def handle(_, _msg), do: :ignore
end
