defmodule BotchiniDiscord.Common.Interactions.About do
  @moduledoc """
  Handles /about slash command
  """

  import Nostrum.Struct.Embed
  alias Nostrum.Constants.InteractionCallbackType
  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias BotchiniDiscord.InteractionBehaviour

  @behaviour InteractionBehaviour

  @impl BotchiniDiscord.InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "about",
      description: "Information about the bot"
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(_interaction, _options) do
    embed =
      %Nostrum.Struct.Embed{}
      |> put_title("Botchini information")
      |> put_field("Version", Application.spec(:botchini, :vsn) |> to_string(), true)
      |> put_field("Author", "Luca\#1813", true)
      |> put_field("Website", "[Link](https://botchini.lucapasquale.dev)", true)
      |> put_field("Uptime", uptime(), true)
      |> put_field("Processes", "#{length(:erlang.processes())}", true)
      |> put_field("Memory Usage", "#{div(:erlang.memory(:total), 1_000_000)} MB", true)

    %{
      type: InteractionCallbackType.channel_message_with_source(),
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
