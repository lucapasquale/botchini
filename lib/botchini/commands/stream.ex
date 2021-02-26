defmodule Botchini.Commands.Stream do
  use Nostrum.Consumer
  alias Nostrum.Api


  def add(msg, [stream_code]) do
    Botchini.Stream.get_or_insert_stream(%Botchini.Stream{code: stream_code})

    Api.create_message!(msg.channel_id, "Added " <> stream_code <> " to your streams!")
  end

  def remove(msg, [stream_code]) do
    Botchini.Stream.delete_stream(%Botchini.Stream{code: stream_code})

    Api.create_message!(msg.channel_id, "Removed " <> stream_code <> " from your streams!")
  end
end
