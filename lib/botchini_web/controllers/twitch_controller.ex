defmodule BotchiniWeb.TwitchController do
  use BotchiniWeb, :controller

  require Logger

  alias Botchini.Creators
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
        Logger.info("twitch_user_id: #{twitch_user_id}")

        case Creators.find_creator_by_twitch_user_id(twitch_user_id) do
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
    {:ok, {user, stream_data}} = Creators.stream_info(creator.code)

    followers = Creators.find_followers_for_creator(creator)
    Logger.info("Stream #{creator.code} is online, sending to #{length(followers)} channels")

    Enum.each(followers, fn follower ->
      Task.start(fn ->
        notify_followers(creator, follower, {user, stream_data})
      end)
    end)
  end

  defp notify_followers(creator, follower, {user, stream_data}) do
    channel_id = follower.discord_channel_id

    msg_response =
      Nostrum.Api.create_message(
        String.to_integer(channel_id),
        embed: Embeds.stream_online(user, stream_data),
        components: [Components.unfollow_stream(creator.code)]
      )

    case msg_response do
      {:error, _err} ->
        Logger.warn("Removing channel since doesn't exist anymore", channel_id: channel_id)
        {:ok} = Creators.unfollow({:twitch, creator.code}, %{channel_id: channel_id})

      _ ->
        :noop
    end
  end
end
