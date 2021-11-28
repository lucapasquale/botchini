defmodule BotchiniDiscord.Interactions do
  @moduledoc """
  Register slash commands and handles interactions
  """

  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct.{ApplicationCommandInteractionData, Interaction}

  alias BotchiniDiscord.Common.Interactions.Info
  alias BotchiniDiscord.Twitch.Interactions.{ConfirmUnfollow, Follow, Following, Stream, Unfollow}

  @spec register_commands() :: any()
  def register_commands do
    [
      Info.get_command(),
      ConfirmUnfollow.get_command(),
      Follow.get_command(),
      Following.get_command(),
      Stream.get_command(),
      Unfollow.get_command()
    ]
    |> Enum.filter(&(!is_nil(&1)))
    |> register_commands(Application.fetch_env!(:botchini, :environment))
  end

  defp register_commands(commands, :prod) do
    Api.bulk_overwrite_global_application_commands(commands)
  end

  defp register_commands(commands, _env) do
    case Application.fetch_env(:botchini, :test_guild_id) do
      {:ok, guild_id} -> Api.bulk_overwrite_guild_application_commands(guild_id, commands)
      _ -> :noop
    end
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
      response =
        interaction
        |> call_interaction(parse_interaction_data(interaction.data))

      Nostrum.Api.create_interaction_response(interaction, response)
    rescue
      err ->
        Logger.error(err)

        Nostrum.Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{content: "Something went wrong :("}
        })
    end
  end

  @spec parse_interaction_data(ApplicationCommandInteractionData.t()) :: [String.t()]
  def parse_interaction_data(interaction_data) do
    case Map.get(interaction_data, :custom_id) do
      nil ->
        options = Map.get(interaction_data, :options) || []
        args = Enum.map(options, fn opt -> opt.value end)

        [interaction_data.name] ++ args

      custom_id ->
        String.split(custom_id, ":")
    end
  end

  defp call_interaction(interaction, ["info"]),
    do: Info.handle_interaction(interaction, %{})

  defp call_interaction(interaction, ["stream", stream_code]),
    do:
      Stream.handle_interaction(interaction, %{
        stream_code: stream_code
      })

  defp call_interaction(interaction, ["follow", stream_code]),
    do:
      Follow.handle_interaction(interaction, %{
        stream_code: stream_code
      })

  defp call_interaction(interaction, ["confirm_unfollow", type, stream_code]),
    do:
      ConfirmUnfollow.handle_interaction(interaction, %{
        type: String.to_atom(type),
        stream_code: stream_code
      })

  defp call_interaction(interaction, ["unfollow", stream_code]),
    do:
      Unfollow.handle_interaction(interaction, %{
        stream_code: stream_code
      })

  defp call_interaction(interaction, ["following"]),
    do: Following.handle_interaction(interaction, %{})

  defp call_interaction(_interaction, _data),
    do: raise("Unknown command")
end
