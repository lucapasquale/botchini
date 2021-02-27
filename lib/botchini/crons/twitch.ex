defmodule Botchini.Crons.Twitch do
  use Tesla

  require Logger
  alias Botchini.Schema.{Stream, StreamFollower}

  plug(Tesla.Middleware.JSON)
  plug(Tesla.Middleware.BaseUrl, "https://api.twitch.tv/helix")

  plug(Tesla.Middleware.Headers, [
    {"client-id", System.get_env("TWITCH_CLIENT_ID")},
    {"authorization", "Bearer " <> System.get_env("TWITCH_TOKEN")}
  ])

  def sync_streams do
    Logger.info("Syncing stream...")

    get_stream_zip(Stream.find_all())
    |> Enum.each(fn [stream, twitch_data] ->
      if stream.online == false and twitch_data != nil do
        send_followers_message(stream)
      end

      Stream.update_stream(stream, %{online: twitch_data != nil})
    end)

    Logger.info("Syncing stream done")
  end

  defp get_stream_zip(streams) do
    query = Enum.map(streams, fn s -> {:user_login, s.code} end)
    {:ok, %{body: body}} = get("/streams", query: query)

    Enum.map(streams, fn stream ->
      twitch_data =
        body
        |> Map.get("data")
        |> Enum.find(fn stream_data -> Map.get(stream_data, "user_login") == stream.code end)

      [stream, twitch_data]
    end)
  end

  defp send_followers_message(stream) do
    followers = StreamFollower.find_all_for_stream(stream.id)

    Enum.map(followers, fn follower ->
      follower.channel_id
      |> String.to_integer()
      |> Nostrum.Api.create_message!(stream.code <> " is online now")
    end)
  end
end