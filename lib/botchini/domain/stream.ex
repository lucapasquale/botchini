defmodule Botchini.Domain.Stream do
  alias Botchini.Schema.{Stream, StreamFollower}

  def following_list(discord_channel_id) do
    streams =
      discord_channel_id
      |> Integer.to_string()
      |> Botchini.Schema.Stream.find_all_for_discord_channel()

    {:ok, streams}
  end

  def follow(code, discord_channel_id) do
    case upsert_stream(format_code(code)) do
      {:error, _} ->
        {:error, :invalid_stream}

      {:ok, stream} ->
        StreamFollower.get_or_insert_follower(%StreamFollower{
          stream_id: stream.id,
          discord_channel_id: Integer.to_string(discord_channel_id)
        })

        {:ok, stream}
    end
  end

  def stop_following(code, discord_channel_id) do
    case Stream.find_by_code(format_code(code)) do
      nil ->
        {:error, :not_found}

      stream ->
        StreamFollower.delete_follower(%StreamFollower{
          stream_id: stream.id,
          discord_channel_id: Integer.to_string(discord_channel_id)
        })

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
