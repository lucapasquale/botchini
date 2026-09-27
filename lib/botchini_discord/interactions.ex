defmodule BotchiniDiscord.Interactions do
  @moduledoc """
  Register slash commands and handles interactions
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Nostrum.Api
  alias Nostrum.Constants.{InteractionCallbackType, InteractionType}
  alias Nostrum.Struct.Interaction

  alias BotchiniDiscord.Common.Interactions.About
  alias BotchiniDiscord.Helpers
  alias BotchiniDiscord.Creators.Interactions.{ConfirmUnfollow, Follow, Info, List, Unfollow}
  alias BotchiniDiscord.Music.Interactions.Music
  alias BotchiniDiscord.Squads.Interactions.Squad

  @deferred_commands ["follow", "info", "music"]

  @error_response %{
    type: InteractionCallbackType.channel_message_with_source(),
    data: %{content: "Something went wrong :("}
  }

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
        is_public =
          {access, command}
          |> command_is_public(Application.fetch_env!(:botchini, :environment))

        if is_public do
          {elem(acc, 0) ++ [command], elem(acc, 1)}
        else
          {elem(acc, 0), elem(acc, 1) ++ [command]}
        end
      end)

    Api.ApplicationCommand.bulk_overwrite_global_commands(public_commands)

    Enum.each(Application.fetch_env!(:botchini, :test_guild_ids), fn guild_id ->
      Api.ApplicationCommand.bulk_overwrite_guild_commands(guild_id, private_commands)
    end)
  end

  @spec handle_interaction(Interaction.t()) :: any()
  def handle_interaction(interaction) do
    Logger.metadata(
      interaction_data: interaction.data,
      guild_id: interaction.guild_id,
      channel_id: interaction.channel_id,
      user_id: interaction.user.id
    )

    Logger.info("Interaction received", interaction_data: interaction.data)

    command = command_name(interaction)

    Tracer.with_span "discord.#{command}", %{kind: :server} do
      start_time = System.monotonic_time()
      deferred = defer_response?(interaction)

      if deferred do
        Api.Interaction.create_response(interaction, %{
          type: InteractionCallbackType.deferred_channel_message_with_source()
        })
      end

      {subcommand, result} = run_interaction(interaction)

      status =
        interaction
        |> send_response(response_of(result), deferred)
        |> interaction_status(result)

      tags = %{
        command: command,
        subcommand: subcommand,
        kind: interaction_kind(interaction),
        status: status
      }

      Tracer.set_attributes(Map.new(tags, fn {key, value} -> {"discord.#{key}", value} end))
      if status == :error, do: Tracer.set_status(:error, "interaction failed")

      :telemetry.execute(
        [:botchini, :discord, :interaction, :stop],
        %{duration: System.monotonic_time() - start_time},
        tags
      )
    end
  end

  defp run_interaction(interaction) do
    {_command, options} = data = Helpers.parse_interaction_data(interaction.data)
    response = call_interaction(interaction, data) |> put_default_allowed_mentions()

    {subcommand_name(options), {:ok, response}}
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__
      Logger.error("Failed to handle interaction: " <> Exception.format(kind, reason, stacktrace))
      Tracer.record_exception(Exception.normalize(kind, reason, stacktrace), stacktrace)

      {"none", {:error, @error_response}}
  end

  defp response_of({_result, response}), do: response

  # A handler can succeed and Discord still reject its response (an invalid
  # payload, or an interaction that expired), which the user sees as a failure too
  defp interaction_status(_send_result, {:error, _response}), do: :error

  defp interaction_status({:error, error}, {:ok, _response}) do
    Logger.error("Discord rejected the interaction response", error: inspect(error))
    :error
  end

  defp interaction_status(_send_result, {:ok, _response}), do: :ok

  defp command_name(%{data: %{custom_id: custom_id}}) when is_binary(custom_id),
    do: custom_id |> String.split("|") |> hd()

  defp command_name(%{data: %{name: name}}) when is_binary(name), do: name
  defp command_name(_interaction), do: "unknown"

  # Subcommands and button actions are parsed as options with an empty value
  defp subcommand_name([%{name: name, value: ""} | _rest]), do: name
  defp subcommand_name(_options), do: "none"

  defp interaction_kind(interaction) do
    cond do
      interaction.type == InteractionType.message_component() -> "button"
      interaction.type == InteractionType.application_command_autocomplete() -> "autocomplete"
      true -> "command"
    end
  end

  # Discord only waits 3 seconds for a response, so commands that call external
  # APIs acknowledge the interaction first and fill in the message when done
  defp defer_response?(interaction) do
    interaction.type == InteractionType.application_command() and
      interaction.data.name in @deferred_commands
  end

  defp send_response(interaction, response, true),
    do: Api.Interaction.edit_response(interaction, response.data)

  defp send_response(interaction, response, false),
    do: Api.Interaction.create_response(interaction, response)

  # Responses echo user input (song terms, squad names), so block @everyone,
  # role and user pings unless an interaction explicitly allows them
  defp put_default_allowed_mentions(%{type: type, data: data} = response) do
    message_types = [
      InteractionCallbackType.channel_message_with_source(),
      InteractionCallbackType.update_message()
    ]

    if type in message_types,
      do: %{response | data: Map.put_new(data, :allowed_mentions, %{parse: []})},
      else: response
  end

  defp put_default_allowed_mentions(response), do: response

  # Set all commands as private while in dev mode
  defp command_is_public(_command_tupple, :dev), do: false

  defp command_is_public({access, _command}, _env) do
    access == :public
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
