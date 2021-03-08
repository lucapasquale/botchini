defmodule BotchiniDiscord.Commands.Basic do
  @moduledoc """
  Handles basic commands to check bot status
  """

  use Nostrum.Consumer
  alias Nostrum.Api
  import Nostrum.Struct.Embed

  def ping(msg) do
    response_msg = Api.create_message!(msg.channel_id, "pong!")

    time = time_diff(response_msg.timestamp, msg.timestamp)
    content = response_msg.content <> "\ntook #{time} ms"

    Api.edit_message(response_msg, content: content)
  end

  def status(msg) do
    embed =
      %Nostrum.Struct.Embed{}
      |> put_title("Botchini status")
      |> put_field("Version", Application.spec(:botchini, :vsn) |> to_string(), true)
      |> put_field("Author", "Luca\#1813", true)
      |> put_field("Source code", "[GitHub](https://github.com/lucapasquale/botchini/)", true)
      |> put_field("Uptime", uptime(), true)
      |> put_field("Processes", "#{length(:erlang.processes())}", true)
      |> put_field("Memory Usage", "#{div(:erlang.memory(:total), 1_000_000)} MB", true)

    Api.create_message!(msg.channel_id, embed: embed)
  end

  defp uptime do
    {time, _} = :erlang.statistics(:wall_clock)

    sec = div(time, 1000)
    {min, sec} = {div(sec, 60), rem(sec, 60)}
    {hours, min} = {div(min, 60), rem(min, 60)}
    {days, hours} = {div(hours, 24), rem(hours, 24)}

    Stream.zip([sec, min, hours, days], ["s", "m", "h", "d"])
    |> Enum.reduce("", fn
      {0, _glyph}, acc -> acc
      {t, glyph}, acc -> " #{t}" <> glyph <> acc
    end)
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
