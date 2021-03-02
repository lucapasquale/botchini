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

  def send_followers_message(twitch_user_id) do
    stream = Stream.find_by_twitch_user_id(twitch_user_id)

    user_data = Botchini.Twitch.API.get_user(stream.code)
    stream_data = Botchini.Twitch.API.get_stream(stream.code)

    Enum.each(StreamFollower.find_all_for_stream(stream.id), fn follower ->
      follower
      |> Map.get(:discord_channel_id)
      |> String.to_integer()
      |> BotchiniDiscord.Events.StreamOnline.send_message({user_data, stream_data})
    end)
  end
end
