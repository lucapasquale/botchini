defmodule BotchiniDiscord.Commands.Stream do
  @moduledoc """
  Handles !stream commands
  """

  use Nostrum.Consumer
  alias Nostrum.Api
  alias Nostrum.Struct.Message

  alias Botchini.Domain
  alias Botchini.Twitch.API
  alias BotchiniDiscord.Messages.StreamOnline

  @spec add(Message.t(), String.t()) :: no_return()
  def add(msg, _stream_code) when is_nil(msg.guild_id),
    do: Api.create_message!(msg.channel_id, "Only available inside servers")

  def add(msg, stream_code) do
    IO.inspect(msg)

    case Domain.Stream.follow(stream_code, %{
           guild_id: Integer.to_string(msg.guild_id),
           channel_id: Integer.to_string(msg.channel_id),
           user_id: Integer.to_string(msg.author.id)
         }) do
      {:error, :invalid_stream} ->
        Api.create_message!(msg.channel_id, "Invalid Twitch stream!")

      {:error, :already_following} ->
        Api.create_message!(msg.channel_id, "Already following!")

      {:ok, stream} ->
        Api.create_message!(msg.channel_id, "Following the stream #{stream.code}!")

        stream_data = API.get_stream(stream.code)

        if stream_data != nil do
          user_data = API.get_user(stream.code)

          StreamOnline.send_message(
            msg.channel_id,
            {user_data, stream_data}
          )
        end
    end
  end

  @spec remove(Message.t(), String.t()) :: no_return()
  def remove(msg, _stream_code) when is_nil(msg.guild_id),
    do: Api.create_message!(msg.channel_id, "Only available inside servers")

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

  @spec list(Message.t()) :: no_return()
  def list(msg) when is_nil(msg.guild_id),
    do: Api.create_message!(msg.channel_id, "Only available inside servers")

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
