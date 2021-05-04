defmodule BotchiniDiscord.Messages.StreamOnline do
  @moduledoc """
  Embed message on Discord for when a stream is online
  """

  use Nostrum.Consumer
  import Nostrum.Struct.Embed

  @spec send_message(integer(), tuple()) ::
          {:ok, Nostrum.Struct.Message.t()} | {:error, any()}
  def send_message(discord_channel_id, {user, stream_data}) do
    stream_url = "https://www.twitch.tv/" <> user.login

    thumbnail_url =
      (stream_data.thumbnail_url || "")
      # Adding random variance to image url to reduce chance of using old cache
      |> String.replace("{width}", Integer.to_string(1280 + Enum.random(-5..5)))
      |> String.replace("{height}", Integer.to_string(720 + Enum.random(-5..5)))

    embed =
      %Nostrum.Struct.Embed{}
      |> put_title(user.display_name <> " is streaming!")
      |> put_description(stream_data.title)
      |> put_url(stream_url)
      |> put_thumbnail(user.profile_image_url)
      |> put_color(6_570_404)
      |> put_image(thumbnail_url)
      |> put_field("Game", stream_data.game_name, true)
      |> put_field("Viewer count", stream_data.viewer_count, true)

    Nostrum.Api.create_message(discord_channel_id, content: stream_url, embed: embed)
  end
end
