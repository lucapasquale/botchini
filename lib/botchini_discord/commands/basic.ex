defmodule BotchiniDiscord.Commands.Basic do
  use Nostrum.Consumer
  alias Nostrum.Api

  def ping(msg) do
    response_msg = Api.create_message!(msg.channel_id, "pong!")

    time = time_diff(response_msg.timestamp, msg.timestamp)
    content = response_msg.content <> "\ntook #{time} ms"

    Api.edit_message(response_msg, content: content)
  end

  defp time_diff(time1, time2, unit \\ :millisecond) do
    from = fn
      %NaiveDateTime{} = x -> x
      x -> NaiveDateTime.from_iso8601!(x)
    end

    {time1, time2} = {from.(time1), from.(time2)}
    NaiveDateTime.diff(time1, time2, unit)
  end
end
