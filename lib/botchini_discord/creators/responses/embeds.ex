defmodule BotchiniDiscord.Creators.Responses.Embeds do
  @moduledoc """
  Generates embed messages for creator commands
  """

  alias Nostrum.Struct.Embed
  import Nostrum.Struct.Embed

  alias Botchini.Creators.Schema.Creator
  alias Botchini.Services

  @spec creator_embed(Creator.t()) :: Embed.t()
  def creator_embed(creator) when creator.service == :twitch do
    user = Services.twitch_user_info(creator.service_id)
    user_url = "https://www.twitch.tv/#{user.login}"

    %Embed{}
    |> put_author(user.display_name, user_url, user.profile_image_url)
    |> put_title(user.display_name)
    |> put_description(user.description)
    |> put_url(user_url)
    |> put_thumbnail(user.profile_image_url)
    |> put_color(6_570_404)
    |> put_footer("Since")
    |> put_timestamp(user.created_at)
  end

  def creator_embed(creator) when creator.service == :youtube do
    channel = Services.youtube_channel_info(creator.service_id)
    channel_url = "https://www.youtube.com/channel/#{channel.id}"

    %Embed{}
    |> put_author(
      channel.snippet["title"],
      channel_url,
      channel.snippet["thumbnails"]["default"]["url"]
    )
    |> put_title(channel.snippet["title"])
    |> put_description(channel.snippet["description"])
    |> put_url(channel_url)
    |> put_thumbnail(channel.snippet["thumbnails"]["high"]["url"])
    |> put_color(16_711_680)
    |> put_footer("Since")
    |> put_timestamp(channel.snippet["publishedAt"])
  end

  @spec twitch_stream_online(Creator.t()) :: Embed.t()
  def twitch_stream_online(creator) do
    user = Services.twitch_user_info(creator.service_id)
    stream = Services.twitch_stream_info(creator.service_id)

    stream_url = "https://www.twitch.tv/#{user.login}"

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
    |> put_timestamp(stream.started_at)
  end

  @spec youtube_video_posted(Creator.t(), String.t()) :: Embed.t()
  def youtube_video_posted(creator, video_id) do
    channel = Services.youtube_channel_info(creator.service_id)
    video = Services.youtube_video_info(video_id)

    channel_url = "https://youtube.com/channel/#{channel.id}"
    video_type = if(is_nil(video.liveStreamingDetails), do: "video", else: "livestream")

    %Embed{}
    |> put_author(
      channel.snippet["title"],
      channel_url,
      channel.snippet["thumbnails"]["default"]["url"]
    )
    |> put_title("New #{video_type} by #{channel.snippet["title"]}")
    |> put_description(video.snippet["title"])
    |> put_url("https://www.youtube.com/watch?v=#{video.id}")
    |> put_color(16_711_680)
    |> put_image(video.snippet["thumbnails"]["high"]["url"])
    |> put_timestamp(video.snippet["publishedAt"])
  end
end
