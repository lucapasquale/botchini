defmodule BotchiniWeb.YoutubeController do
  use BotchiniWeb, :controller

  require Logger

  @spec challenge(Plug.Conn.t(), any) :: Plug.Conn.t()
  def challenge(conn, _params) do
    challenge = conn.params["hub.challenge"]

    text(conn, challenge)
  end

  @spec notification(Plug.Conn.t(), any) :: Plug.Conn.t()
  def notification(conn, _params) do
    IO.inspect(conn)

    conn.body_params
    |> IO.inspect(label: "body")
    |> Map.get("feed")
    |> IO.inspect(label: "feed")
    |> Map.get("entry")
    |> IO.inspect(label: "entry")

    text(conn, "ok")
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
