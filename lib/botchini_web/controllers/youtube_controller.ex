defmodule BotchiniWeb.YoutubeController do
  use BotchiniWeb, :controller

  require Logger

  alias Botchini.Creators
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

    Logger.info("Received webhook from youtube")
    video_id = Map.get(entry, "{http://www.youtube.com/xml/schemas/2015}videoId")

    case video_already_posted(entry, video_id) do
      true ->
        text(conn, "ok")

      false ->
        VideoCache.insert(video_id)
        channel_id = Map.get(entry, "{http://www.youtube.com/xml/schemas/2015}channelId")

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

  defp video_already_posted(entry, video_id) do
    {:ok, published_at, _} = DateTime.from_iso8601(entry["published"])
    {:ok, updated_at, _} = DateTime.from_iso8601(entry["updated"])

    VideoCache.has_video_id(video_id) ||
      DateTime.diff(updated_at, published_at, :second) > 5 * 60
  end

  defp send_new_video_messages(creator, video_id) do
    followers = Creators.find_followers_for_creator(creator)
    Logger.info("Channel #{creator.name} posted, sending to #{length(followers)} channels")

    Enum.each(followers, fn follower ->
      Task.start(fn -> notify_followers(creator, follower, video_id) end)
    end)
  end

  defp notify_followers(creator, follower, video_id) do
    channel_id = follower.discord_channel_id

    msg_response =
      Nostrum.Api.create_message(
        String.to_integer(channel_id),
        embed: Embeds.youtube_video_posted(creator, video_id),
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
