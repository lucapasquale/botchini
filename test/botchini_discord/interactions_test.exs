defmodule BotchiniDiscordTest.InteractionsTest do
  use ExUnit.Case, async: false

  use Patch

  @moduletag :capture_log

  alias BotchiniDiscord.Interactions
  alias Nostrum.Struct.{ApplicationCommandInteractionData, Interaction, User}

  setup do
    test_pid = self()
    handler_id = "interactions-test-#{inspect(test_pid)}"

    :telemetry.attach(
      handler_id,
      [:botchini, :discord, :interaction, :stop],
      fn _event, _measurements, metadata, _config -> send(test_pid, {:interaction, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp command_interaction(name) do
    %Interaction{
      type: 2,
      data: %ApplicationCommandInteractionData{name: name, options: nil},
      user: %User{id: 1},
      channel_id: 2
    }
  end

  test "reports a successful command" do
    patch(Nostrum.Api.Interaction, :create_response, :ok)

    Interactions.handle_interaction(command_interaction("about"))

    assert_received {:interaction,
                     %{command: "about", subcommand: "none", kind: "command", status: :ok}}
  end

  test "routes /stream to the screen sharing command" do
    patch(Nostrum.Api.Interaction, :create_response, :ok)

    Interactions.handle_interaction(command_interaction("stream"))

    assert_received {:interaction, %{command: "stream", status: :ok}}

    assert_called(
      Nostrum.Api.Interaction.create_response(_interaction, %{
        data: %{content: "Can only be used inside a server!"}
      })
    )
  end

  test "reports a command that raised and still answers the user" do
    patch(Nostrum.Api.Interaction, :create_response, :ok)

    Interactions.handle_interaction(command_interaction("not_a_command"))

    assert_received {:interaction, %{command: "not_a_command", status: :error}}
    assert_called(Nostrum.Api.Interaction.create_response(_interaction, %{type: 4}))
  end

  test "reports a response rejected by Discord as a failure" do
    patch(Nostrum.Api.Interaction, :create_response, {:error, %{status_code: 400}})

    Interactions.handle_interaction(command_interaction("about"))

    assert_received {:interaction, %{command: "about", status: :error}}
  end
end
