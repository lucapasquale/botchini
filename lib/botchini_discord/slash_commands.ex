defmodule BotchiniDiscord.SlashCommands do
  @moduledoc """
  Register slash commands and handles interactions
  """

  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct.Interaction

  alias BotchiniDiscord.SlashCommands.{Follow, Following, Info, Stream, Unfollow}

  @spec register_commands() :: :ok
  def register_commands do
    commands = [
      Follow.get_command(),
      Following.get_command(),
      Info.get_command(),
      Stream.get_command(),
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

  @spec handle_interaction(Interaction.t()) :: any()
  def handle_interaction(interaction) do
    IO.inspect(interaction)

    Logger.metadata(
      interaction_data: interaction.data,
      guild_id: interaction.guild_id,
      channel_id: interaction.channel_id,
      user_id: interaction.member && interaction.member.user.id
    )

    Logger.info("Interaction received")

    try do
      Nostrum.Api.create_interaction_response(interaction, %{
        type: 4,
        data: interaction_response(interaction)
      })
    rescue
      err ->
        Logger.error(err)

        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "Something went wrong :("}
        })
    end
  end

  defp interaction_response(interaction) do
    case parse_interaction(interaction.data) do
      {"info", []} ->
        Info.handle_interaction(interaction)

      {"stream", [stream_code]} ->
        Stream.handle_interaction(interaction, stream_code)

      {"follow", [stream_code]} ->
        Follow.handle_interaction(interaction, stream_code)

      {"unfollow", [stream_code]} ->
        Unfollow.handle_interaction(interaction, stream_code)

      {"following", []} ->
        Following.handle_interaction(interaction)

      _ ->
        %{content: "Unknown command"}
    end
  end

  @spec parse_interaction(map()) :: {String.t(), [String.t()]}
  def parse_interaction(interaction_data) do
    arguments =
      interaction_data
      |> Map.get(:options, [])
      |> Enum.map(fn opt -> opt.value end)

    {interaction_data.name, arguments}
  end
end
