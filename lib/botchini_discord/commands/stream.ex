defmodule BotchiniDiscord.Commands.Stream do
  use Nostrum.Consumer
  alias Nostrum.Api

  alias Botchini.Domain

  def add(msg, stream_code) do
    case Domain.Stream.follow(stream_code, Integer.to_string(msg.channel_id)) do
      {:error, :invalid_stream} ->
        Api.create_message!(msg.channel_id, "Invalid Twitch stream!")

      {:error, :already_following} ->
        Api.create_message!(msg.channel_id, "Already following!")

      {:ok, stream} ->
        Api.create_message!(msg.channel_id, "Following the stream #{stream.code}!")

        stream_data = Botchini.Twitch.API.get_stream(stream.code)

        if stream_data != nil do
          user_data = Botchini.Twitch.API.get_user(stream.code)

          BotchiniDiscord.Events.StreamOnline.send_message(
            msg.channel_id,
            {user_data, stream_data}
          )
        end
    end
  end

  def remove(msg, stream_code) do
    case Domain.Stream.stop_following(stream_code, Integer.to_string(msg.channel_id)) do
      {:error, :not_found} ->
        Api.create_message!(msg.channel_id, "Stream #{stream_code} was not being followed")

      {:ok} ->
        Api.create_message!(
          msg.channel_id,
          "Removed #{stream_code} from your following streams"
        )
    end
  end

  def list(msg) do
    case Domain.Stream.following_list(Integer.to_string(msg.channel_id)) do
      {:ok, []} ->
        Api.create_message!(msg.channel_id, "Not following any stream!")

      {:ok, streams} ->
        stream_list =
          streams
          |> Enum.map(fn stream -> stream.code end)
          |> Enum.join("\n")

        Api.create_message!(msg.channel_id, "Following streams:\n" <> stream_list)
    end
  end
end
