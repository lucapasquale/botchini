defmodule Botchini.Domain.Stream do
  alias Botchini.Schema.{Stream, StreamFollower}

  def follow(code, discord_channel_id) do
    stream =
      case Stream.find_by_code(code) do
        %Stream{} = existing ->
          existing

        nil ->
          twitch_user = Botchini.Twitch.API.get_user(code)
          event_subscription = Botchini.Twitch.API.add_stream_webhook(twitch_user["id"])

          Stream.insert(%Stream{
            code: code,
            twitch_user_id: twitch_user["id"],
            twitch_subscription_id: event_subscription["id"]
          })
      end

    StreamFollower.get_or_insert_follower(%StreamFollower{
      stream_id: stream.id,
      discord_channel_id: Integer.to_string(discord_channel_id)
    })

    {:ok, stream}
  end

  def stop_following(code, discord_channel_id) do
    case Stream.find_by_code(code) do
      nil ->
        {:error, :not_found}

      stream ->
        StreamFollower.delete_follower(%StreamFollower{
          stream_id: stream.id,
          discord_channel_id: Integer.to_string(discord_channel_id)
        })

        {:ok}
    end
  end
end
