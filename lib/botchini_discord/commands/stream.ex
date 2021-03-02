defmodule BotchiniDiscord.Commands.Stream do
  use Nostrum.Consumer
  alias Nostrum.Api

  alias Botchini.Domain

  def list(msg) do
    response =
      case Domain.Stream.following_list(msg.channel_id) do
        {:ok, []} ->
          "Not following any stream!"

        {:ok, streams} ->
          streams
          |> Enum.map(fn stream -> stream.code end)
          |> Enum.join("\n")
          |> (&("Following streams:\n" <> &1)).()
      end

    Api.create_message!(msg.channel_id, response)
  end

  def add(msg, stream_code) do
    response =
      case Domain.Stream.follow(stream_code, msg.channel_id) do
        {:ok, stream} -> "Following the stream " <> stream.code <> "!"
        {:error, _} -> "Invalid Twitch stream!"
      end

    Api.create_message!(msg.channel_id, response)
  end

  def remove(msg, stream_code) do
    response =
      case Domain.Stream.stop_following(stream_code, msg.channel_id) do
        {:ok} -> "Removed " <> stream_code <> " from your following streams"
        {:error, :not_found} -> "Stream " <> stream_code <> " was not being followed"
      end

    Api.create_message!(msg.channel_id, response)
  end
end
