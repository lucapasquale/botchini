defmodule Botchini.Domain.Stream do
  @moduledoc """
  Handles business logic for streams
  """

  alias Botchini.Twitch.API
  alias Botchini.Schema.{Guild, Stream, StreamFollower}

  @spec follow(String.t(), %{guild: Guild.t(), channel_id: String.t(), user_id: String.t()}) ::
          {:ok, Stream.t()} | {:error, :invalid_stream} | {:error, :already_following}
  def follow(code, %{guild: guild, channel_id: channel_id, user_id: user_id}) do
    case upsert_stream(format_code(code)) do
      {:error, _} ->
        {:error, :invalid_stream}

      {:ok, stream} ->
        case StreamFollower.find(stream.id, channel_id) do
          nil ->
            StreamFollower.insert(%StreamFollower{
              stream_id: stream.id,
              guild_id: guild.id,
              discord_channel_id: channel_id,
              discord_user_id: user_id
            })

            {:ok, stream}

          _follower ->
            {:error, :already_following}
        end
    end
  end

  @spec stop_following(String.t(), String.t()) :: {:ok} | {:error, :not_found}
  def stop_following(code, discord_channel_id) do
    case Stream.find_by_code(format_code(code)) do
      nil ->
        {:error, :not_found}

      stream ->
        StreamFollower.find(stream.id, discord_channel_id)
        |> StreamFollower.delete()

        if StreamFollower.find_all_for_stream(stream.id) == [] do
          API.delete_stream_webhook(stream.twitch_subscription_id)
          Stream.delete_stream(stream)
        end

        {:ok}
    end
  end

  @spec following_list(String.t()) :: {:ok, [Stream.t()]}
  def following_list(discord_channel_id) do
    streams = Botchini.Schema.Stream.find_all_for_discord_channel(discord_channel_id)
    {:ok, streams}
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
        case API.get_user(code) do
          nil ->
            {:error, :invalid_stream}

          twitch_user ->
            event_subscription = API.add_stream_webhook(twitch_user["id"])

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
