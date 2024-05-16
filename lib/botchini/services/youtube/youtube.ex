defmodule Botchini.Services.Youtube do
  @moduledoc """
  Handles communication with YouTube API
  """

  require Logger

  alias Botchini.Services.Youtube.Structs.{Channel, Video}

  @spec search_channels(String.t()) :: list(Channel.t())
  def search_channels(term) do
    resp =
      Req.get!(
        api(),
        url: "/search",
        params: [part: "snippet", type: "channel", q: term]
      )

    case Map.get(resp.body, "items") do
      nil ->
        []

      items ->
        Enum.map(items, fn item ->
          Channel.new(%{id: item["id"]["channelId"], snippet: item["snippet"]})
        end)
    end
  end

  @spec get_channel(String.t()) :: Channel.t() | nil
  def get_channel(channel_id) do
    resp =
      Req.get!(
        api(),
        url: "/channels",
        params: [part: "snippet", id: channel_id]
      )

    case Map.get(resp.body, "items") do
      nil ->
        nil

      items ->
        List.first(items)
        |> Channel.new()
    end
  end

  @spec get_video(String.t()) :: Video.t() | nil
  def get_video(video_id) do
    resp =
      Req.get!(
        api(),
        url: "/videos",
        params: [part: "snippet,liveStreamingDetails", id: video_id]
      )

    case Map.get(resp.body, "items") do
      nil ->
        nil

      items ->
        List.first(items)
        |> Video.new()
    end
  end

  @spec manage_channel_pubsub(String.t(), boolean()) :: {:ok}
  def manage_channel_pubsub(channel_id, subscribe) do
    callback_url = "#{Application.fetch_env!(:botchini, :host)}/api/youtube/webhooks/callback"
    topic_url = "https://www.youtube.com/xml/feeds/videos.xml?channel_id=#{channel_id}"

    Req.post!(
      url: "https://pubsubhubbub.appspot.com/subscribe",
      form: [
        "hub.verify": "async",
        "hub.mode": if(subscribe, do: "subscribe", else: "unsubscribe"),
        "hub.callback": callback_url,
        "hub.topic": topic_url,
        "hub.secret": Application.fetch_env!(:botchini, :youtube_webhook_secret)
      ]
    )

    {:ok}
  end

  @spec get_video_id_from_url(String.t()) :: String.t()
  def get_video_id_from_url(url) do
    video_id_regex = ~r/^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*/

    case Regex.run(video_id_regex, url) do
      nil ->
        nil

      match ->
        List.last(match)
    end
  end

  defp api do
    Req.new(
      base_url: "https://www.googleapis.com/youtube/v3",
      params: [key: Application.fetch_env!(:botchini, :youtube_api_key)]
    )
  end
end
