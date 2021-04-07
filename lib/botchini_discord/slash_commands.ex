defmodule BotchiniDiscord.SlashCommands do
  @moduledoc """
  All slash commands available
  """

  alias BotchiniDiscord.SlashCommands.{Stream}

  def assign_commands() do
    Stream.get_commands()
    |> Enum.each(fn command ->
      case Nostrum.Api.create_guild_application_command(459_166_748_009_037_826, command) do
        {:error, message} -> IO.inspect(message)
        _ -> :noop
      end
    end)
  end

  def handle_interaction(interaction) do
    case parse_interaction(interaction.data) do
      ["stream", "add", stream_code] ->
        Stream.add(interaction, stream_code)

      ["stream", "remove", stream_code] ->
        Stream.remove(interaction, stream_code)

      ["following"] ->
        Stream.list(interaction)

      _ ->
        :noop
    end
  end

  def respond_interaction(interaction, content) do
    Nostrum.Api.create_interaction_response(interaction, %{
      type: 4,
      data: %{content: content}
    })
  end

  defp parse_interaction(interaction_data) do
    case Map.get(interaction_data, :options) do
      nil ->
        [interaction_data.name]

      options ->
        option = Enum.at(options, 0)

        case Map.get(option, :options) do
          nil -> [interaction_data.name, option.name]
          options -> [interaction_data.name, option.name, Enum.at(options, 0).value]
        end
    end
  end
end
