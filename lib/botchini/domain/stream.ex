defmodule Botchini.Domain.Stream do
  alias Botchini.Schema.{Stream, StreamFollower}

  def following_list(discord_channel_id) do
    streams = Botchini.Schema.Stream.find_all_for_discord_channel(discord_channel_id)
    {:ok, streams}
  end

  def follow(code, discord_channel_id) do
    case upsert_stream(format_code(code)) do
      {:error, _} ->
        {:error, :invalid_stream}

      {:ok, stream} ->
        case StreamFollower.find(stream.id, discord_channel_id) do
          nil ->
            StreamFollower.insert(%StreamFollower{
              stream_id: stream.id,
              discord_channel_id: discord_channel_id
            })

            {:ok, stream}

          _follower ->
            {:error, :already_following}
        end
    end
  end

  def stop_following(code, discord_channel_id) do
    case Stream.find_by_code(format_code(code)) do
      nil ->
        {:error, :not_found}

      stream ->
        StreamFollower.find(stream.id, discord_channel_id)
        |> StreamFollower.delete()

        if StreamFollower.find_all_for_stream(stream.id) == [] do
          Botchini.Twitch.API.delete_stream_webhook(stream.twitch_subscription_id)
          Stream.delete_stream(stream)
        end

        {:ok}
    end
  end

  defp format_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end

  defp upsert_stream(code) do
    case Stream.find_by_code(code) do
      %Stream{} = existing ->
        {:ok, existing}

      nil ->
        case Botchini.Twitch.API.get_user(code) do
          nil ->
            {:error, :invalid_stream}

          twitch_user ->
            event_subscription = Botchini.Twitch.API.add_stream_webhook(twitch_user["id"])

            stream =
              Stream.insert(%Stream{
                code: code,
                twitch_user_id: twitch_user["id"],
                twitch_subscription_id: event_subscription["id"]
              })

            {:ok, stream}
        end
    end
  end
end
