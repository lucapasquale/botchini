defmodule Botchini.Twitch.Routes.WebhookCallback do
  @moduledoc """
  Routes for twitch events callback
  """

  require Logger

  alias Botchini.Twitch
  alias BotchiniDiscord.Responses.{Components, Embeds}

  @spec call(Plug.Conn.t()) :: {:ok, any()} | {:error, :not_found}
  def call(conn) do
    case get_event_type(conn.body_params) do
      {:unknown, _} ->
        {:error, :not_found}

      {:confirm_subscription, challenge} ->
        {:ok, challenge}

      {:stream_online, subscription} ->
        twitch_user_id = subscription["condition"]["broadcaster_user_id"]

        case Twitch.find_stream_by_twitch_user_id(twitch_user_id) do
          nil ->
            {:error, :not_found}

          stream ->
            send_stream_online_messages(stream)
            {:ok, "ok"}
        end
    end
  end

  @spec get_event_type(any()) ::
          {:confirm_subscription, String.t()}
          | {:stream_online, any()}
          | {:unknown, :invalid_event}
  def get_event_type(body) do
    subscription = body["subscription"]

    if subscription["status"] == "webhook_callback_verification_pending" do
      {:confirm_subscription, body["challenge"]}
    else
      case subscription["type"] do
        "stream.online" -> {:stream_online, subscription}
        _ -> {:unknown, :invalid_event}
      end
    end
  end

  defp send_stream_online_messages(stream) do
    {:ok, {user, stream_data}} = Twitch.stream_info(stream.code)

    followers = Twitch.find_followers_for_stream(stream)
    Logger.info("Stream #{stream.code} is online, sending to #{length(followers)} channels")

    Enum.each(followers, fn follower ->
      Task.start(fn ->
        notify_followers(stream, follower, {user, stream_data})
      end)
    end)
  end

  defp notify_followers(stream, follower, {user, stream_data}) do
    channel_id = follower.discord_channel_id

    msg_response =
      Nostrum.Api.create_message(
        String.to_integer(channel_id),
        embed: Embeds.stream_online(user, stream_data),
        components: [Components.unfollow_stream(stream.code)]
      )

    case msg_response do
      {:error, _err} ->
        Logger.warn("Removing channel since doesn't exist anymore", channel_id: channel_id)
        {:ok} = Twitch.unfollow(stream.code, %{channel_id: channel_id})

      _ ->
        :noop
    end
  end
end
