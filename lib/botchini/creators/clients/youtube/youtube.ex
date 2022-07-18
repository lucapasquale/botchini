defmodule Botchini.Creators.Clients.Youtube do
  @moduledoc """
  Handles communication with YouTube API
  """

  use Tesla
  alias Tesla.Multipart
  require Logger

  alias Botchini.Creators.Clients.Youtube.Structs

  plug(Tesla.Middleware.JSON)
  plug(Tesla.Middleware.Logger)

  plug(Tesla.Middleware.Query,
    key: Application.fetch_env!(:botchini, :youtube_api_key)
  )

  @youtube_api "https://www.googleapis.com/youtube/v3"

  @spec search_channels(String.t()) :: list(Structs.Channel.t())
  def search_channels(term) do
    {:ok, %{body: body}} =
      get("#{@youtube_api}/search",
        query: [part: "snippet", type: "channel", q: term]
      )

    case Map.get(body, "items") do
      nil ->
        []

      items ->
        Enum.map(items, fn item ->
          Structs.Channel.new(%{id: item["id"]["channelId"], snippet: item["snippet"]})
        end)
    end
  end

  @spec get_channel(String.t()) :: Structs.Channel.t() | nil
  def get_channel(code) do
    {:ok, %{body: body}} =
      get("#{@youtube_api}/channels",
        query: [part: "snippet", forUsername: code]
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
      get("#{@youtube_api}/channels",
        query: [part: "snippet", id: channel_id]
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
        query: [part: "snippet,liveStreamingDetails", id: video_id]
      )

    case Map.get(body, "items") do
      nil ->
        nil

      items ->
        List.first(items)
        |> Structs.Video.new()
    end
  end

  @spec manage_channel_pubsub(String.t(), boolean()) :: {:ok}
  def manage_channel_pubsub(channel_id, subscribe) do
    callback_url = "#{Application.fetch_env!(:botchini, :host)}/api/youtube/webhooks/callback"
    topic_url = "https://www.youtube.com/xml/feeds/videos.xml?channel_id=#{channel_id}"

    mp =
      Multipart.new()
      |> Multipart.add_field("hub.callback", callback_url)
      |> Multipart.add_field("hub.topic", topic_url)
      |> Multipart.add_field("hub.verify", "async")
      |> Multipart.add_field("hub.mode", if(subscribe, do: "subscribe", else: "unsubscribe"))

    {:ok, _} = post("https://pubsubhubbub.appspot.com/subscribe", mp)
    {:ok}
  end
end
