defmodule Botchini.Twitch.Callback do
  alias Botchini.Schema.{Stream, StreamFollower}

  def handle_callback(conn) do
    case get_event_type(conn.body_params) do
      {:confirm_subscription, challenge} ->
        %{status: 200, body: challenge}

      {:stream_online, subscription} ->
        send_followers_message(subscription["condition"]["broadcaster_user_id"])
        %{status: 200, body: "OK"}

      {:error, _} ->
        %{status: 404, body: "Invalid event"}
    end
  end

  defp get_event_type(body) do
    subscription = body["subscription"]

    if subscription["status"] == "webhook_callback_verification_pending" do
      {:confirm_subscription, body["challenge"]}
    else
      case subscription["type"] do
        "stream.online" -> {:stream_online, subscription}
        _ -> {:error, :invalid_event}
      end
    end
  end

  defp send_followers_message(twitch_user_id) do
    stream = Stream.find_by_twitch_user_id(twitch_user_id)
    followers = StreamFollower.find_all_for_stream(stream.id)

    Enum.each(followers, fn follower ->
      follower.discord_channel_id
      |> String.to_integer()
      |> Nostrum.Api.create_message!(stream.code <> " is online now!")
    end)
  end
end
