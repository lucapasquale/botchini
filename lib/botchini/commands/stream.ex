defmodule Botchini.Commands.Stream do
  use Nostrum.Consumer
  alias Nostrum.Api

  alias Botchini.Schema.{Stream, StreamFollower}

  def add(msg, stream_code) do
    stream = Stream.get_or_insert_stream(%Stream{code: stream_code})

    StreamFollower.get_or_insert_follower(%StreamFollower{
      stream_id: stream.id,
      channel_id: Integer.to_string(msg.channel_id)
    })

    Api.create_message!(msg.channel_id, "Following the stream " <> stream_code)
  end

  def remove(msg, stream_code) do
    case Stream.find_by_code(stream_code) do
      nil ->
        Api.create_message!(
          msg.channel_id,
          "Stream " <> stream_code <> " was not being followed"
        )

      stream ->
        StreamFollower.delete_follower(%StreamFollower{
          stream_id: stream.id,
          channel_id: Integer.to_string(msg.channel_id)
        })

        remaining_followers = StreamFollower.find_all_for_stream(stream.id)

        if remaining_followers == [] do
          Stream.delete_stream(stream)
        end

        Api.create_message!(
          msg.channel_id,
          "Removed " <> stream_code <> " from your following streams"
        )
    end
  end
end
