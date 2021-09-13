defmodule BotchiniDiscordTest.InteractionsTest do
  use ExUnit.Case

  import BotchiniDiscord.Interactions

  describe "parse_interaction_data" do
    test "parse interation data for command" do
      interaction_data = %{name: "command_name"}

      {:command, ["command_name"]} = parse_interaction_data(interaction_data)
    end

    test "parse interation data with option" do
      interaction_data = %{
        name: "command_name",
        options: [%{value: "sub_command_value"}]
      }

      {:command, ["command_name", "sub_command_value"]} = parse_interaction_data(interaction_data)
    end

    test "parse interation data for component" do
      interaction_data = %{
        custom_id: "command:sub_command"
      }

      {:component, ["command", "sub_command"]} = parse_interaction_data(interaction_data)
    end
  end
end
