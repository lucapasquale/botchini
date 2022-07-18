defmodule Botchini.Services do
  @moduledoc """
  Handles calling external services
  """

  alias Botchini.Creators.Schema.Creator
  alias Botchini.Services.{Twitch, Youtube}

  @spec twitch_user_info(String.t()) :: Twitch.Structs.User.t()
  def twitch_user_info(user_id) do
    Twitch.get_user(user_id)
  end

  @spec twitch_stream_info(String.t()) :: Twitch.Structs.Stream.t() | nil
  def twitch_stream_info(service_id) do
    Twitch.get_stream(service_id)
  end

  @spec youtube_channel_info(String.t()) :: Youtube.Structs.Channel.t() | nil
  def youtube_channel_info(channel_id) do
    Youtube.get_channel(channel_id)
  end

  @spec youtube_video_info(String.t()) :: Youtube.Structs.Video.t() | nil
  def youtube_video_info(video_id) do
    Youtube.get_video(video_id)
  end

  @spec search_channel(Creator.services(), String.t()) ::
          {:error, :not_found} | {:ok, {any(), any()}}
  def search_channel(:twitch, term) do
    case Twitch.search_channels(term) do
      channels when channels == [] ->
        {:error, :not_found}

      channels ->
        channel = hd(channels)
        {:ok, {channel.id, channel.display_name}}
    end
  end

  def search_channel(:youtube, term) do
    case Youtube.search_channels(term) do
      channels when channels == [] ->
        {:error, :not_found}

      channels ->
        channel = hd(channels)
        {:ok, {channel.id, channel.snippet["title"]}}
    end
  end

  @spec subscribe_to_service(Creator.services(), String.t()) :: String.t() | nil
  def subscribe_to_service(:twitch, service_id) do
    event_subscription = Twitch.add_stream_webhook(service_id)
    event_subscription["id"]
  end

  def subscribe_to_service(:youtube, service_id) do
    {:ok} = Youtube.manage_channel_pubsub(service_id, true)
    nil
  end
end
