defmodule BotchiniDiscord.Messages.StreamOnline do
  @moduledoc """
  Embed message on Discord for when a stream is online
  """

  alias Nostrum.Struct.Embed
  import Nostrum.Struct.Embed

  alias Botchini.Twitch.API.Structs.{Stream, User}

  @spec generate_embed(User.t(), Stream.t()) :: Embed.t()
  def generate_embed(user, stream) do
    stream_url = "https://www.twitch.tv/" <> user.login

    thumbnail_url =
      Map.get(stream, :thumbnail_url, "")
      # Adding random variance to image url to reduce chance of using old cache
      |> String.replace("{width}", Integer.to_string(1280 + Enum.random(-5..5)))
      |> String.replace("{height}", Integer.to_string(720 + Enum.random(-5..5)))

    %Embed{}
    |> put_author(user.display_name, stream_url, user.profile_image_url)
    |> put_title(user.display_name <> " is streaming!")
    |> put_description(stream.title)
    |> put_url(stream_url)
    |> put_thumbnail(user.profile_image_url)
    |> put_color(6_570_404)
    |> put_image(thumbnail_url)
    |> put_field("Game", stream.game_name, true)
    |> put_field("Viewer count", Integer.to_string(stream.viewer_count), true)
    |> put_footer("Since")
    |> put_timestamp(DateTime.to_iso8601(stream.started_at))
  end
end
