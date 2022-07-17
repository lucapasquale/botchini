defmodule Botchini.Creators.Clients.Youtube do
  @moduledoc """
  Handles communication with YouTube API
  """

  use Tesla
  alias Tesla.Multipart

  alias Botchini.Creators.Clients.Youtube.Structs

  plug(Tesla.Middleware.JSON)
  plug(Tesla.Middleware.Logger)

  plug(Tesla.Middleware.Query, [
    {"key", Application.fetch_env!(:botchini, :youtube_api_key)}
  ])

  @spec get_channel(String.t()) :: Structs.Channel.t() | nil
  def get_channel(code) do
    {:ok, %{body: body}} =
      get("https://youtube.googleapis.com/youtube/v3/channels",
        query: [
          part: "snippet,statistics",
          forUsername: code
        ]
      )

    case Map.get(body, "items") do
      nil ->
        nil

      items ->
        List.first(items)
        |> Structs.Channel.new()
    end
  end

  @spec get_channel_by_id(String.t()) :: Structs.Channel.t() | nil
  def get_channel_by_id(channel_id) do
    {:ok, %{body: body}} =
      get("https://youtube.googleapis.com/youtube/v3/channels",
        query: [
          part: "snippet,statistics",
          id: channel_id
        ]
      )

    case Map.get(body, "items") do
      nil ->
        nil

      items ->
        List.first(items)
        |> Structs.Channel.new()
    end
  end

  @spec get_video(String.t()) :: Structs.Channel.t() | nil
  def get_video(video_id) do
    {:ok, %{body: body}} =
      get("https://www.googleapis.com/youtube/v3/videos",
        query: [
          part: "snippet,statistics,liveStreamingDetails",
          id: video_id
        ]
      )

    case Map.get(body, "items") do
      nil ->
        nil

      items ->
        List.first(items)
        |> Structs.Video.new()
    end
  end

  @spec manage_channel_pubsub(String.t(), boolean()) :: any()
  def manage_channel_pubsub(channel_id, subscribe) do
    callback_url =
      "https://#{Application.fetch_env!(:botchini, :host)}/api/youtube/webhooks/callback"

    topic_url = "https://www.youtube.com/xml/feeds/videos.xml?channel_id=#{channel_id}"

    mp =
      Multipart.new()
      |> Multipart.add_field("hub.callback", callback_url)
      |> Multipart.add_field("hub.topic", topic_url)
      |> Multipart.add_field("hub.verify", "async")
      |> Multipart.add_field("hub.mode", if(subscribe, do: "subscribe", else: "unsubscribe"))

    {:ok, _} = post("https://pubsubhubbub.appspot.com/subscribe", mp)
  end
end
