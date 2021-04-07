defmodule BotchiniDiscord.SlashCommands do
  @moduledoc """
  Register slash commands and handles interactions
  """

  alias Nostrum.Api
  alias Nostrum.Struct.Interaction
  alias BotchiniDiscord.SlashCommands.{Basic, Stream}

  @spec register_commands() :: :ok
  def register_commands do
    commands = Basic.get_commands() ++ Stream.get_commands()

    commands
    |> Enum.each(fn command ->
      if Application.fetch_env!(:botchini, :environment) === :prod do
        Api.create_global_application_command(command)
      else
        case Application.fetch_env(:botchini, :test_guild_id) do
          {:ok, guild_id} -> Api.create_guild_application_command(guild_id, command)
          _ -> :noop
        end
      end
    end)
  end

  @spec handle_interaction(Interaction.t()) :: no_return()
  def handle_interaction(interaction) do
    case parse_interaction(interaction.data) do
      ["status"] ->
        Basic.status(interaction)

      ["follow", stream_code] ->
        Stream.follow(interaction, stream_code)

      ["unfollow", stream_code] ->
        Stream.unfollow(interaction, stream_code)

      ["following"] ->
        Stream.list(interaction)

      _ ->
        respond_interaction(interaction, "Unknown command")
    end
  end

  @spec parse_interaction(map()) :: [String.t()]
  def parse_interaction(interaction_data) do
    case Map.get(interaction_data, :options) do
      nil ->
        [interaction_data.name]

      options ->
        [interaction_data.name, Enum.at(options, 0).value]
    end
  end

  @spec respond_interaction(Interaction.t(), String.t()) :: no_return()
  def respond_interaction(interaction, content) do
    Api.create_interaction_response(interaction, %{
      type: 4,
      data: %{content: content}
    })
  end
end