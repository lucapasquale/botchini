defmodule Botchini.Routes.Twitch do
  @moduledoc """
  Routes for twitch events callback
  """

  require Logger

  alias Botchini.Domain
  alias Botchini.Schema.{Stream, StreamFollower}
  alias Botchini.Twitch.API
  alias BotchiniDiscord.Messages.StreamOnline

  @spec webhook_callback(Plug.Conn.t()) :: %{status: Integer.t(), body: String.t()}
  def webhook_callback(conn) do
    case get_event_type(conn.body_params) do
      {:unknown, _} ->
        %{status: 404, body: "Invalid event"}

      {:confirm_subscription, challenge} ->
        %{status: 200, body: challenge}

      {:stream_online, subscription} ->
        case Stream.find_by_twitch_user_id(subscription["condition"]["broadcaster_user_id"]) do
          nil ->
            %{status: 404, body: "Invalid stream"}

          stream ->
            send_stream_online_messages(stream)
            %{status: 200, body: "OK"}
        end
    end
  end

  @spec get_event_type(any()) ::
          {:confirm_subscription, String.t()}
          | {:stream_online, any()}
          | {:unknown, :invalid_event}
  def get_event_type(body) do
    subscription = body["subscription"]

    if subscription["status"] == "webhook_callback_verification_pending" do
      {:confirm_subscription, body["challenge"]}
    else
      case subscription["type"] do
        "stream.online" -> {:stream_online, subscription}
        _ -> {:unknown, :invalid_event}
      end
    end
  end

  defp send_stream_online_messages(stream) do
    user_data = API.get_user(stream.code)
    stream_data = API.get_stream(stream.code)

    followers = StreamFollower.find_all_for_stream(stream.id)

    Logger.info("Stream #{stream.code} is online, sending to #{length(followers)} channels")

    Enum.each(followers, fn follower ->
      Task.start(fn ->
        send_followers_message(stream, follower, {user_data, stream_data})
      end)
    end)
  end

  defp send_followers_message(stream, follower, {user_data, stream_data}) do
    channel_id = Map.get(follower, :discord_channel_id)

    msg_response =
      StreamOnline.send_message(
        String.to_integer(channel_id),
        {user_data, stream_data}
      )

    case msg_response do
      {:error, _err} ->
        Logger.warn("Removing channel since doesn't exist anymore",
          channel_id: channel_id
        )

        Domain.Stream.stop_following(stream.code, channel_id)

      _ ->
        :noop
    end
  end
end
