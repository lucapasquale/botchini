defmodule BotchiniDiscord.Events.StreamOnline do
  use Nostrum.Consumer

  def send_message(follower, stream) do
    follower.discord_channel_id
    |> String.to_integer()
    |> Nostrum.Api.create_message!(stream.code <> " is online now!")
  end
end
