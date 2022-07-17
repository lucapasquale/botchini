defmodule BotchiniWeb.YoutubeController do
  use BotchiniWeb, :controller

  require Logger

  alias Botchini.Creators
  alias BotchiniDiscord.Creators.Responses.Embeds

  @spec challenge(Plug.Conn.t(), any) :: Plug.Conn.t()
  def challenge(conn, _params) do
    challenge = conn.params["hub.challenge"]

    text(conn, challenge)
  end

  @spec notification(Plug.Conn.t(), any) :: Plug.Conn.t()
  def notification(conn, _params) do
    IO.inspect(conn)

    entry =
      conn.body_params
      |> Map.get("feed")
      |> Map.get("entry")

    channel_id = Map.get(entry, "{http://www.youtube.com/xml/schemas/2015}channelId")
    video_id = Map.get(entry, "{http://www.youtube.com/xml/schemas/2015}videoId")
    IO.inspect({channel_id, video_id})

    case Creators.find_creator_by_youtube_channel_id(channel_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> render(:"404")

      creator ->
        send_new_video_messages(creator, video_id)
        text(conn, "ok")
    end
  end

  defp send_new_video_messages(creator, video_id) do
    {:ok, {channel, video}} =
      Creators.youtube_video_info(creator.metadata["channel_id"], video_id)

    IO.inspect(channel)
    IO.inspect(video)

    followers = Creators.find_followers_for_creator(creator)

    Logger.info(
      "Channel #{creator.code} posted a new video, sending to #{length(followers)} channels"
    )

    Enum.each(followers, fn follower ->
      Task.start(fn ->
        notify_followers(creator, follower, {channel, video})
      end)
    end)

    :ok
  end

  defp notify_followers(creator, follower, {channel, video}) do
    msg_response =
      Nostrum.Api.create_message(
        String.to_integer(follower.discord_channel_id),
        embed: Embeds.youtube_video(channel, video)
        # components: [Components.unfollow_stream(creator.code)]
      )

    case msg_response do
      {:error, _err} ->
        Logger.warn("Removing channel since doesn't exist anymore",
          channel_id: follower.discord_channel_id
        )

        Creators.unfollow({:twitch, creator.code}, %{channel_id: follower.discord_channel_id})

      _ ->
        :noop
    end
  end
end

# body: %{
#   "feed" => %{
#     "entry" => %{
#       "author" => %{
#         "name" => "Luca Pasquale",
#         "uri" => "https://www.youtube.com/channel/UCpZOwKhGAc38GhLC7XWq6vg"
#       },
#       "id" => "yt:video:q2_Bh4A4fG4",
#       "link" => %{
#         "#content" => nil,
#         "-href" => "https://www.youtube.com/watch?v=q2_Bh4A4fG4",
#         "-rel" => "alternate"
#       },
#       "published" => "2022-07-16T20:33:18+00:00",
#       "title" => "2",
#       "updated" => "2022-07-16T20:33:50.882435395+00:00",
#       "{http://www.youtube.com/xml/schemas/2015}channelId" => "UCpZOwKhGAc38GhLC7XWq6vg",
#       "{http://www.youtube.com/xml/schemas/2015}videoId" => "q2_Bh4A4fG4"
#     },
#     "link" => [
#       %{
#         "#content" => nil,
#         "-href" => "https://pubsubhubbub.appspot.com",
#         "-rel" => "hub"
#       },
#       %{
#         "#content" => nil,
#         "-href" => "https://www.youtube.com/xml/feeds/videos.xml?channel_id=UCpZOwKhGAc38GhLC7XWq6vg",
#         "-rel" => "self"
#       }
#     ],
#     "title" => "YouTube video feed",
#     "updated" => "2022-07-16T20:33:50.882435395+00:00"
#   }
# }

# channel link = feed -> entry -> author -> uri
# channel name = feed -> entry -> author -> name
# stream link = feed -> entry -> link -> href
# stream title = feed -> entry -> title
# stream start = feed -> entry -> published

# precisa pegar:
# - thumbnail
# - avatar canal
# - viewers?
