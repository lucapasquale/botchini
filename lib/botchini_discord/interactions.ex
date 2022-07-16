defmodule BotchiniDiscord.Interactions do
  @moduledoc """
  Register slash commands and handles interactions
  """

  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct.Interaction

  alias BotchiniDiscord.Common.Interactions.Info
  alias BotchiniDiscord.Helpers
  alias BotchiniDiscord.Creators.Interactions.{ConfirmUnfollow, Follow, List, Stream, Unfollow}

  @spec register_commands() :: any()
  def register_commands do
    [
      Info.get_command(),
      ConfirmUnfollow.get_command(),
      List.get_command(),
      Follow.get_command(),
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
      data = Helpers.parse_interaction_data(interaction.data)
      response = call_interaction(interaction, data)

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

  defp call_interaction(interaction, {"info", opt}),
    do: Info.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"stream", opt}),
    do: Stream.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"follow", opt}),
    do: Follow.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"confirm_unfollow", opt}),
    do: ConfirmUnfollow.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"unfollow", opt}),
    do: Unfollow.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"list", opt}),
    do: List.handle_interaction(interaction, opt)

  defp call_interaction(_interaction, _data),
    do: raise("Unknown command")
end
