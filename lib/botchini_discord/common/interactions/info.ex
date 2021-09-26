defmodule BotchiniDiscord.Common.Interactions.Info do
  @behaviour BotchiniDiscord.Interaction

  @moduledoc """
  Handles /info slash command
  """

  import Nostrum.Struct.Embed

  @impl BotchiniDiscord.Interaction
  @spec get_command() :: map()
  def get_command,
    do: %{
      name: "info",
      description: "Information about the bot"
    }

  @impl BotchiniDiscord.Interaction
  @spec handle_interaction(Nostrum.Struct.Interaction.t(), map()) :: map()
  def handle_interaction(_interaction, _payload) do
    embed =
      %Nostrum.Struct.Embed{}
      |> put_title("Botchini information")
      |> put_field("Version", Application.spec(:botchini, :vsn) |> to_string(), true)
      |> put_field("Author", "Luca\#1813", true)
      |> put_field("Source code", "[GitHub](https://github.com/lucapasquale/botchini/)", true)
      |> put_field("Uptime", uptime(), true)
      |> put_field("Processes", "#{length(:erlang.processes())}", true)
      |> put_field("Memory Usage", "#{div(:erlang.memory(:total), 1_000_000)} MB", true)

    %{
      type: 4,
      data: %{embeds: [embed]}
    }
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
end