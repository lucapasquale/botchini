defmodule BotchiniWeb.Api.YoutubeController do
  use BotchiniWeb, :controller

  require Logger

  alias Botchini.{Cache, Creators, Services}
  alias BotchiniDiscord.Creators.Responses.{Components, Embeds}

  # 30 days
  @event_ttl 1_000 * 60 * 60 * 24 * 30

  @spec challenge(Plug.Conn.t(), any) :: Plug.Conn.t()
  def challenge(conn, _params) do
    challenge = conn.params["hub.challenge"]

    text(conn, challenge)
  end

  @spec notification(Plug.Conn.t(), any) :: Plug.Conn.t()
  def notification(conn, _params) do
    case is_request_valid?(conn, Application.fetch_env!(:botchini, :environment)) do
      false ->
        conn
        |> put_status(:not_found)
        |> text("not found")

      true ->
        process_webhook(conn)
    end
  end

  defp is_request_valid?(_conn, :dev), do: true

  defp is_request_valid?(conn, _) do
    [raw_body] = Map.get(conn.assigns, :raw_body)
    webhook_secret = Application.fetch_env!(:botchini, :youtube_webhook_secret)

    hmac =
      :crypto.mac(:hmac, :sha, webhook_secret, raw_body)
      |> Base.encode16(case: :lower)

    header_signature =
      conn
      |> get_req_header("x-hub-signature")
      |> Enum.at(0)

    "sha1=" <> hmac == header_signature
  end

  defp process_webhook(conn) do
    event =
      conn.body_params
      |> Map.get("feed")
      |> Map.get("entry")

    channel_id = Map.get(event, "{http://www.youtube.com/xml/schemas/2015}channelId")
    video_id = Map.get(event, "{http://www.youtube.com/xml/schemas/2015}videoId")

    Logger.info("Received webhook from youtube channel #{channel_id}, video #{video_id}")

    cache_key = "youtube_event:#{channel_id}:#{video_id}"

    if should_notify?(event, cache_key) do
      send_new_video_messages(channel_id, video_id)

      {:ok, _} = Cache.set(cache_key, @event_ttl, fn -> true end)
    end

    text(conn, "ok")
  end

  defp should_notify?(event, cache_key) do
    {:ok, notified} = Cache.get(cache_key)

    {:ok, published_at, _} = DateTime.from_iso8601(event["published"])
    published_recently = abs(DateTime.diff(published_at, DateTime.utc_now(), :hour)) <= 24

    !notified && published_recently
  end

  defp send_new_video_messages(channel_id, video_id) do
    creator = Creators.find_by_service(:youtube, channel_id)
    followers = Creators.find_followers_for_creator(creator)
    Logger.info("Channel #{creator.name} posted, sending to #{length(followers)} channels")

    yt_channel = Services.youtube_channel_info(creator.service_id)
    yt_video = Services.youtube_video_info(video_id)

    Enum.each(followers, fn follower ->
      Task.start(fn -> notify_followers(creator, follower, {yt_channel, yt_video}) end)
    end)
  end

  defp notify_followers(creator, follower, {channel, video}) do
    channel_id = follower.discord_channel_id

    msg_response =
      Nostrum.Api.create_message(
        String.to_integer(channel_id),
        embed: Embeds.youtube_video_posted(channel, video),
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
