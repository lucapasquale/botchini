defmodule BotchiniDiscord.SlashCommands do
  @moduledoc """
  Register slash commands and handles interactions
  """

  require Logger

  alias Nostrum.Api
  alias Nostrum.Struct.Interaction
  alias BotchiniDiscord.SlashCommands.{Follow, Following, Status, Unfollow}

  @spec register_commands() :: :ok
  def register_commands do
    commands = [
      Follow.get_command(),
      Following.get_command(),
      Status.get_command(),
      Unfollow.get_command()
    ]

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
    Logger.info("Interaction received", interaction: %{data: interaction.data})

    try do
      response = interaction_response(interaction)

      Nostrum.Api.create_interaction_response(interaction, %{
        type: 4,
        data: response
      })

      Logger.info("Interaction response",
        interaction: %{data: interaction.data},
        response: response
      )
    rescue
      err ->
        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "Something went wrong :("}
        })

        Logger.error("Interaction error",
          error: err,
          interaction: interaction
        )
    end
  end

  defp interaction_response(interaction) do
    if is_nil(interaction.member) do
      %{content: "Can't use commands from DMs!"}
    else
      case parse_interaction(interaction.data) do
        ["status"] ->
          Status.handle_interaction(interaction)

        ["follow", stream_code] ->
          Follow.handle_interaction(interaction, stream_code)

        ["unfollow", stream_code] ->
          Unfollow.handle_interaction(interaction, stream_code)

        ["following"] ->
          Following.handle_interaction(interaction)

        _ ->
          Api.create_interaction_response(interaction, %{
            type: 4,
            data: %{content: "Unknown command"}
          })
      end
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
end
