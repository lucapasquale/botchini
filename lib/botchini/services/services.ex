defmodule Botchini.Services do
  @moduledoc """
  Handles calling external services
  """

  alias Botchini.Creators.Schema.Creator
  alias Botchini.Services.{Twitch, Youtube}

  @spec twitch_user_info(String.t()) :: {:ok, Twitch.Structs.User.t()} | {:error, nil}
  def twitch_user_info(user_id) do
    Twitch.get_user(user_id)
  end

  @spec twitch_stream_info(String.t()) :: {:ok, Twitch.Structs.Stream.t()} | {:error, nil}
  def twitch_stream_info(service_id) do
    Twitch.get_stream(service_id)
  end

  @spec youtube_channel_info(String.t()) :: {:ok, Youtube.Structs.Channel.t()} | {:error, nil}
  def youtube_channel_info(channel_id) do
    Youtube.get_channel(channel_id)
  end

  @spec youtube_video_info(String.t()) :: {:ok, Youtube.Structs.Video.t()} | {:error, nil}
  def youtube_video_info(video_id) do
    Youtube.get_video(video_id)
  end

  @spec get_user(Creator.services(), String.t()) ::
          {:error, :not_found} | {:ok, {String.t(), String.t()}}
  def get_user(:twitch, service_id) do
    case Twitch.get_user(service_id) do
      {:error, _} -> {:error, :not_found}
      {:ok, user} -> {:ok, {user.id, user.display_name}}
    end
  end

  def get_user(:youtube, service_id) do
    case Youtube.get_channel(service_id) do
      {:error, _} -> {:error, :not_found}
      {:ok, channel} -> {:ok, {channel.id, channel.snippet["title"]}}
    end
  end

  @spec search_channel(Creator.services(), String.t()) ::
          {:error, :not_found} | {:ok, {String.t(), String.t()}}
  def search_channel(:twitch, term) do
    # Sometimes Twitch search returns inconsistent results, so we
    # try to find exact match for searched term, if none found uses channel search
    case Twitch.get_user_by_user_login(term) do
      {:error, _} ->
        case Twitch.search_channels(term) do
          channels when channels == [] ->
            {:error, :not_found}

          channels ->
            channel = hd(channels)
            {:ok, {channel.id, channel.display_name}}
        end

      {:ok, user} ->
        {:ok, {user.id, user.display_name}}
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

  @spec unsubscribe_from_service(Creator.services(), {String.t(), String.t()}) :: {:ok}
  def unsubscribe_from_service(:twitch, {_service_id, webhook_id}) do
    Twitch.delete_stream_webhook(webhook_id)
    {:ok}
  end

  def unsubscribe_from_service(:youtube, {service_id, _}) do
    Youtube.manage_channel_pubsub(service_id, false)
    {:ok}
  end
end
