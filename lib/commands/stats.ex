defmodule Botchini.Commands.Stats do
  use Nostrum.Consumer
  alias Nostrum.Api

  def consume(msg) do
    Api.create_message!(msg.channel_id, "Uptime: " <> uptime())
  end

  defp uptime do
    {time, _} = :erlang.statistics(:wall_clock)

    min = div(time, 1000 * 60)
    {hours, min} = {div(min, 60), rem(min, 60)}
    {days, hours} = {div(hours, 24), rem(hours, 24)}

    Stream.zip([min, hours, days], ["m", "h", "d"])
    |> Enum.reduce("", fn
      {0, _glyph}, acc -> acc
      {t, glyph}, acc -> " #{t}" <> glyph <> acc
    end)
  end
end
