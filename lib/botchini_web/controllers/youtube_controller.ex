defmodule BotchiniWeb.YoutubeController do
  use BotchiniWeb, :controller

  require Logger

  alias Botchini.{Creators, Services}
  alias Botchini.Services.Youtube.VideoCache
  alias BotchiniDiscord.Creators.Responses.{Components, Embeds}

  @spec challenge(Plug.Conn.t(), any) :: Plug.Conn.t()
  def challenge(conn, _params) do
    challenge = conn.params["hub.challenge"]

    text(conn, challenge)
  end

  @spec notification(Plug.Conn.t(), any) :: Plug.Conn.t()
  def notification(conn, _params) do
    entry =
      conn.body_params
      |> Map.get("feed")
      |> Map.get("entry")

    channel_id = Map.get(entry, "{http://www.youtube.com/xml/schemas/2015}channelId")
    Logger.info("Received webhook from youtube channel #{channel_id}")

    video_id = Map.get(entry, "{http://www.youtube.com/xml/schemas/2015}videoId")

    case VideoCache.has_video_id(video_id) do
      true ->
        text(conn, "ok")

      false ->
        VideoCache.insert(video_id)

        case Creators.find_by_service(:youtube, channel_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> render(:"404")

          creator ->
            send_new_video_messages(creator, video_id)
            text(conn, "ok")
        end
    end
  end

  defp send_new_video_messages(creator, video_id) do
    followers = Creators.find_followers_for_creator(creator)
    Logger.info("Channel #{creator.name} posted, sending to #{length(followers)} channels")

    channel = Services.youtube_channel_info(creator.service_id)
    video = Services.youtube_video_info(video_id)

    Enum.each(followers, fn follower ->
      Task.start(fn -> notify_followers(creator, follower, {channel, video}) end)
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
        Logger.warn("Removing channel since doesn't exist anymore", channel_id: channel_id)
        {:ok, _} = Creators.unfollow(creator.id, %{channel_id: channel_id})

      _ ->
        :noop
    end
  end
end
