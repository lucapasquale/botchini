defmodule Botchini.Routes.Twitch do
  @moduledoc """
  Routes for twitch events callback
  """

  require Logger

  alias Botchini.Twitch.API
  alias BotchiniDiscord.Messages.StreamOnline
  alias Botchini.Domain
  alias Botchini.Schema.{Stream, StreamFollower}

  @spec webhook_callback(Plug.Conn.t()) :: %{status: Integer.t(), body: String.t()}
  def webhook_callback(conn) do
    case get_event_type(conn.body_params) do
      {:confirm_subscription, challenge} ->
        %{status: 200, body: challenge}

      {:stream_online, subscription} ->
        case Stream.find_by_twitch_user_id(subscription["condition"]["broadcaster_user_id"]) do
          nil ->
            %{status: 404, body: "Invalid stream"}

          stream ->
            send_followers_message(stream)
            %{status: 200, body: "OK"}
        end

      {:unknown, _} ->
        %{status: 404, body: "Invalid event"}
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

  defp send_followers_message(stream) do
    user_data = API.get_user(stream.code)
    stream_data = API.get_stream(stream.code)

    Enum.each(StreamFollower.find_all_for_stream(stream.id), fn follower ->
      channel_id = Map.get(follower, :discord_channel_id)

      case StreamOnline.send_message(String.to_integer(channel_id), {user_data, stream_data}) do
        {:error, _err} ->
          Logger.warn("Channel #{channel_id} doesn't exist anymore")

        _ ->
          :noop
      end
    end)
  end
end
