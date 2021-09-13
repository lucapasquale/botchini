defmodule BotchiniDiscord.Interactions do
  @moduledoc """
  Register slash commands and handles interactions
  """

  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct.Interaction

  alias BotchiniDiscord.Interactions.{
    ConfirmUnfollow,
    Follow,
    Following,
    Info,
    Stream,
    Unfollow
  }

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
    Logger.metadata(
      interaction_data: interaction.data,
      guild_id: interaction.guild_id,
      channel_id: interaction.channel_id,
      user_id: interaction.member && interaction.member.user.id
    )

    Logger.info("Interaction received")

    try do
      interaction
      |> Nostrum.Api.create_interaction_response(interaction_response(interaction))
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
      {:command, ["info"]} ->
        Info.handle_interaction(interaction)

      {:command, ["stream", stream_code]} ->
        Stream.handle_interaction(interaction, stream_code)

      {_, ["follow", stream_code]} ->
        Follow.handle_interaction(interaction, stream_code)

      {:component, ["confirm_unfollow", type, stream_code]} ->
        ConfirmUnfollow.handle_interaction(interaction, %{
          type: String.to_atom(type),
          stream_code: stream_code
        })

      {_, ["unfollow", stream_code]} ->
        Unfollow.handle_interaction(interaction, stream_code)

      {:command, ["following"]} ->
        Following.handle_interaction(interaction)

      _ ->
        %{content: "Unknown command"}
    end
  end

  @spec parse_interaction(map()) :: {:command | :component, [String.t()]}
  def parse_interaction(interaction_data) do
    case Map.get(interaction_data, :custom_id) do
      nil ->
        args =
          interaction_data
          |> Map.get(:options, [])
          |> Enum.map(fn opt -> opt.value end)

        {:command, [interaction_data.name] ++ args}

      custom_id ->
        {:component, String.split(custom_id, ":")}
    end
  end
end
