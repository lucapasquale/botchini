defmodule BotchiniWeb.TwitchController do
  use BotchiniWeb, :controller

  require Logger

  alias Botchini.{Creators, Services}
  alias BotchiniDiscord.Creators.Responses.{Components, Embeds}

  @spec callback(Plug.Conn.t(), any) :: Plug.Conn.t()
  def callback(conn, _params) do
    case request_is_valid?(conn, Application.fetch_env!(:botchini, :environment)) do
      false ->
        conn
        |> put_status(:not_found)
        |> text("not found")

      true ->
        get_event_type(conn.body_params)
        |> process_event(conn)
    end
  end

  defp request_is_valid?(_conn, :dev), do: true

  defp request_is_valid?(conn, _) do
    message_id = get_header(conn, "twitch-eventsub-message-id")
    message_timestamp = get_header(conn, "twitch-eventsub-message-timestamp")
    [body] = Map.get(conn.assigns, :raw_body)
    payload = message_id <> message_timestamp <> body

    webhook_secret = Application.fetch_env!(:botchini, :twitch_webhook_secret)

    hmac =
      :crypto.mac(:hmac, :sha256, webhook_secret, payload)
      |> Base.encode16(case: :lower)

    "sha256=" <> hmac == get_header(conn, "twitch-eventsub-message-signature")
  end

  defp get_header(conn, header_name) do
    conn |> get_req_header(header_name) |> Enum.at(0)
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

  defp process_event({:confirm_subscription, challenge}, conn) do
    text(conn, challenge)
  end

  defp process_event({:stream_online, subscription}, conn) do
    twitch_user_id = subscription["condition"]["broadcaster_user_id"]
    Logger.info("Received webhook for twitch user #{twitch_user_id}")

    case Creators.find_by_service(:twitch, twitch_user_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("not found")

      creator ->
        send_stream_online_messages(conn, creator)
    end
  end

  defp process_event(_, conn) do
    conn
    |> put_status(:not_found)
    |> text("not found")
  end

  defp send_stream_online_messages(conn, creator) do
    with followers <- Creators.find_followers_for_creator(creator),
         {:ok, user} <- Services.twitch_user_info(creator.service_id),
         {:ok, stream} <- Services.twitch_stream_info(creator.service_id) do
      Logger.info("Stream #{creator.name} is online, sending to #{length(followers)} channels")

      Enum.each(followers, fn follower ->
        Task.start(fn -> notify_followers(creator, follower, {user, stream}) end)
      end)

      text(conn, "ok")
    else
      _ ->
        Logger.warning("Failed to load Twitch stream for #{creator.name}")

        conn
        |> put_status(:not_found)
        |> text("not found")
    end
  end

  defp notify_followers(creator, follower, {user, stream}) do
    channel_id = follower.discord_channel_id

    msg_response =
      Nostrum.Api.Message.create(
        String.to_integer(channel_id),
        embed: Embeds.twitch_stream_online(user, stream),
        components: [Components.unfollow_creator(creator.service, creator.service_id)]
      )

    case msg_response do
      {:error, _err} ->
        Logger.warning("Removing channel since doesn't exist anymore", channel_id: channel_id)
        {:ok, _} = Creators.unfollow(creator.id, %{channel_id: channel_id})

      _ ->
        :noop
    end
  end
end
