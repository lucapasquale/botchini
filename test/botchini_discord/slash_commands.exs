defmodule BotchiniDiscordTest.SlashCommands do
  use ExUnit.Case

  import BotchiniDiscord.SlashCommands

  describe "parse_interaction" do
    test "parse interation data with only no options" do
      interaction_data = %{"name" => "command_name"}

      assert parse_interaction(interaction_data) == ["command_name"]
    end

    test "parse interation data with option" do
      interaction_data = %{
        "name" => "command_name",
        "options" => [%{value => "sub_command_value"}]
      }

      assert parse_interaction(interaction_data) == ["command_name", "sub_command_value"]
    end
  end
end
