defmodule Botchini.Commands.Stream do
  use Nostrum.Consumer
  alias Nostrum.Api

  alias Botchini.Schema.{Stream, StreamFollower}

  def add(msg, stream_code) do
    stream =
      case Stream.find_by_code(stream_code) do
        %Stream{} = existing ->
          existing

        nil ->
          twitch_user = Botchini.Twitch.API.get_user(stream_code)
          sub = Botchini.Twitch.API.add_stream_webhook(twitch_user["id"])

          Stream.insert(%Stream{
            code: stream_code,
            twitch_user_id: twitch_user["id"],
            twitch_subscription_id: sub["id"]
          })
      end

    StreamFollower.get_or_insert_follower(%StreamFollower{
      stream_id: stream.id,
      discord_channel_id: Integer.to_string(msg.channel_id)
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
          discord_channel_id: Integer.to_string(msg.channel_id)
        })

        Api.create_message!(
          msg.channel_id,
          "Removed " <> stream_code <> " from your following streams"
        )
    end
  end
end
