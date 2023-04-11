defmodule BotchiniDiscord.Interactions do
  @moduledoc """
  Register slash commands and handles interactions
  """

  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct.Interaction

  alias BotchiniDiscord.Common.Interactions.About
  alias BotchiniDiscord.Helpers
  alias BotchiniDiscord.Creators.Interactions.{ConfirmUnfollow, Follow, Info, List, Unfollow}
  alias BotchiniDiscord.Music.Interactions.Music
  alias BotchiniDiscord.Squads.Interactions.Squad

  @spec register_commands() :: any()
  def register_commands do
    {public_commands, private_commands} =
      [
        {:public, About.get_command()},
        {:public, ConfirmUnfollow.get_command()},
        {:public, Follow.get_command()},
        {:public, Info.get_command()},
        {:public, List.get_command()},
        {:public, Unfollow.get_command()},
        {:private, Squad.get_command()},
        {:private, Music.get_command()}
      ]
      |> Enum.filter(&(!is_nil(elem(&1, 1))))
      |> Enum.reduce({[], []}, fn {access, command}, acc ->
        if command_is_public({access, command}) do
          {elem(acc, 0) ++ [command], elem(acc, 1)}
        else
          {elem(acc, 0), elem(acc, 1) ++ [command]}
        end
      end)

    register_commands(public_commands, Application.fetch_env!(:botchini, :environment))
    register_commands(private_commands, Application.fetch_env!(:botchini, :environment))
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

  defp command_is_public({:public, _command}), do: true

  defp command_is_public(_command_tupple) do
    Application.fetch_env!(:botchini, :environment) == :dev
  end

  defp register_commands(commands, :dev) do
    case Application.fetch_env(:botchini, :test_guild_id) do
      {:ok, guild_id} ->
        Api.bulk_overwrite_guild_application_commands(guild_id, commands)

      _ ->
        :noop
    end
  end

  defp register_commands(commands, _env) do
    Api.bulk_overwrite_global_application_commands(commands)
  end

  defp call_interaction(interaction, {"about", opt}),
    do: About.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"info", opt}),
    do: Info.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"follow", opt}),
    do: Follow.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"confirm_unfollow", opt}),
    do: ConfirmUnfollow.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"unfollow", opt}),
    do: Unfollow.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"list", opt}),
    do: List.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"squad", opt}),
    do: Squad.handle_interaction(interaction, opt)

  defp call_interaction(interaction, {"music", opt}),
    do: Music.handle_interaction(interaction, opt)

  defp call_interaction(_interaction, _data),
    do: raise("Unknown interaction command")
end
