defmodule BotchiniWeb.TwitchController do
  use BotchiniWeb, :controller

  require Logger

  alias Botchini.{Creators, Services}
  alias BotchiniDiscord.Creators.Responses.{Components, Embeds}

  @spec callback(Plug.Conn.t(), any) :: Plug.Conn.t()
  def callback(conn, _params) do
    case get_event_type(conn.body_params) do
      {:unknown, _} ->
        conn
        |> put_status(:not_found)
        |> render(:"404")

      {:confirm_subscription, challenge} ->
        text(conn, challenge)

      {:stream_online, subscription} ->
        twitch_user_id = subscription["condition"]["broadcaster_user_id"]
        Logger.info("Received webhook for twitch", twitch_user_id: twitch_user_id)

        case Creators.find_by_service(:twitch, twitch_user_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> render(:"404")

          creator ->
            send_stream_online_messages(creator)
            text(conn, "ok")
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

  defp send_stream_online_messages(creator) do
    followers = Creators.find_followers_for_creator(creator)
    Logger.info("Stream #{creator.name} is online, sending to #{length(followers)} channels")

    user = Services.twitch_user_info(creator.service_id)
    stream = Services.twitch_stream_info(creator.service_id)

    Enum.each(followers, fn follower ->
      Task.start(fn -> notify_followers(creator, follower, {user, stream}) end)
    end)
  end

  defp notify_followers(creator, follower, {user, stream}) do
    channel_id = follower.discord_channel_id

    msg_response =
      Nostrum.Api.create_message(
        String.to_integer(channel_id),
        embed: Embeds.twitch_stream_online(user, stream),
        components: [Components.unfollow_creator(creator.service, creator.service_id)]
      )

    case msg_response do
      {:error, _err} ->
        Logger.warn("Removing channel since doesn't exist anymore", channel_id: channel_id)
        {:ok, _} = Creators.unfollow(creator.id, %{channel_id: channel_id})

      _ ->
        :noop
    end
  end
end
