defmodule BotchiniDiscord.Interactions do
  @moduledoc """
  Register slash commands and handles interactions
  """

  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct.Interaction

  alias BotchiniDiscord.Interactions

  @spec register_commands() :: :ok
  def register_commands do
    [
      Interactions.ConfirmUnfollow.get_command(),
      Interactions.Follow.get_command(),
      Interactions.Following.get_command(),
      Interactions.Info.get_command(),
      Interactions.Play.get_command(),
      Interactions.Stop.get_command(),
      Interactions.Stream.get_command(),
      Interactions.Unfollow.get_command()
    ]
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.each(fn command ->
      register_command(command, Application.fetch_env!(:botchini, :environment))
    end)
  end

  defp register_command(command, :prod) do
    Api.create_global_application_command(command)
  end

  defp register_command(command, _env) do
    case Application.fetch_env(:botchini, :test_guild_id) do
      {:ok, guild_id} -> Api.create_guild_application_command(guild_id, command)
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

  @spec parse_interaction_data(map()) :: {:command | :component, [String.t()]}
  def parse_interaction_data(interaction_data) do
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

  defp call_interaction(interaction, {:command, ["info"]}),
    do: Interactions.Info.handle_interaction(interaction, %{})

  defp call_interaction(interaction, {:command, ["stream", stream_code]}),
    do: Interactions.Stream.handle_interaction(interaction, %{stream_code: stream_code})

  defp call_interaction(interaction, {_, ["follow", stream_code]}),
    do: Interactions.Follow.handle_interaction(interaction, %{stream_code: stream_code})

  defp call_interaction(interaction, {:component, ["confirm_unfollow", type, stream_code]}),
    do:
      Interactions.ConfirmUnfollow.handle_interaction(interaction, %{
        type: String.to_atom(type),
        stream_code: stream_code
      })

  defp call_interaction(interaction, {_, ["unfollow", stream_code]}),
    do: Interactions.Unfollow.handle_interaction(interaction, %{stream_code: stream_code})

  defp call_interaction(interaction, {:command, ["following"]}),
    do: Interactions.Following.handle_interaction(interaction, %{})

  defp call_interaction(interaction, {:command, ["play", url]}),
    do: Interactions.Play.handle_interaction(interaction, %{url: url})

  defp call_interaction(interaction, {:command, ["stop"]}),
    do: Interactions.Stop.handle_interaction(interaction, %{})

  defp call_interaction(_interaction, _data),
    do: raise("Unknown command")
end
