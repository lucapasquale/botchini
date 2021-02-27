defmodule Botchini.Commands.Stream do
  use Nostrum.Consumer
  alias Nostrum.Api

  alias Botchini.Schema.{Stream, StreamFollower}

  def consume(msg, args) do
    case args do
      ["add", stream_code] -> add(msg, stream_code)
      ["remove", stream_code] -> remove(msg, stream_code)
      _ -> help(msg)
    end
  end

  defp add(msg, stream_code) do
    stream = Stream.get_or_insert_stream(%Stream{code: stream_code})

    StreamFollower.get_or_insert_follower(%StreamFollower{
      stream_id: stream.id,
      channel_id: Integer.to_string(msg.channel_id)
    })

    Api.create_message!(msg.channel_id, "Following the stream " <> stream_code)
  end

  defp remove(msg, stream_code) do
    stream = Stream.find_by_code(stream_code)

    if stream != nil do
      StreamFollower.delete_follower(%StreamFollower{
        stream_id: stream.id,
        channel_id: Integer.to_string(msg.channel_id)
      })

      remaining_followers = StreamFollower.find_all_for_stream(stream.id)

      if (remaining_followers == []) do
        Stream.delete_stream(stream)
      end
    end

    Api.create_message!(
      msg.channel_id,
      "Removed " <> stream_code <> " from your following streams"
    )
  end

  defp help(msg) do
    # TODO: Send message with all !stream commands
    Api.create_message!(msg.channel_id, "Invalid `" <> msg.content <> "` command")
  end
end
