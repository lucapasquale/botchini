defmodule BotchiniDiscord.Events.StreamOnline do
  @moduledoc """
  Embed message on Discord for when a stream is online
  """

  use Nostrum.Consumer

  import Nostrum.Struct.Embed

  def send_message(discord_channel_id, {user_data, stream_data}) do
    stream_url = "https://www.twitch.tv/" <> user_data["login"]

    thumbnail_url =
      stream_data["thumbnail_url"]
      |> String.replace("{width}", "1280")
      |> String.replace("{height}", "720")

    embed =
      %Nostrum.Struct.Embed{}
      |> put_title(user_data["display_name"] <> " started streaming!")
      |> put_description(stream_data["title"])
      |> put_url(stream_url)
      |> put_thumbnail(user_data["profile_image_url"])
      |> put_color(6_570_404)
      |> put_image(thumbnail_url)
      |> put_field("Game", stream_data["game_name"], true)
      |> put_field("Viewer count", stream_data["viewer_count"], true)

    Nostrum.Api.create_message!(discord_channel_id, content: stream_url, embed: embed)
  end
end
