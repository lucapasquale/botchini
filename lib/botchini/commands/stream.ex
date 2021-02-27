defmodule Botchini.Commands.Stream do
  use Nostrum.Consumer
  alias Nostrum.Api

  alias Botchini.Schema.Stream

  def consume(msg, args) do
    case args do
      ["add", stream_code] -> add(msg, stream_code)
      ["remove", stream_code] -> remove(msg, stream_code)
      _ -> help(msg)
    end
  end

  defp add(msg, stream_code) do
    Stream.get_or_insert_stream(%Stream{code: stream_code})

    Api.create_message!(msg.channel_id, "Added " <> stream_code <> " to your streams!")
  end

  defp remove(msg, [stream_code]) do
    Stream.delete_stream(%Stream{code: stream_code})

    Api.create_message!(msg.channel_id, "Removed " <> stream_code <> " from your streams!")
  end

  defp help(msg) do
    Api.create_message!(msg.channel_id, "Invalid `!stream` command")
  end
end
