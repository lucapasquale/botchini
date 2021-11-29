defmodule BotchiniDiscordTest.InteractionsTest do
  use ExUnit.Case

  alias BotchiniDiscord.Helpers

  describe "parse_interaction_data" do
    test "parse interation data for command" do
      interaction_data = %{name: "command", custom_id: nil, options: []}

      {"command", []} = Helpers.parse_interaction_data(interaction_data)
    end

    test "parse interation data with options" do
      interaction_data = %{
        name: "command",
        custom_id: nil,
        options: [
          %{name: "option1", value: "value1"},
          %{name: "option2", value: "value2"}
        ]
      }

      assert Helpers.parse_interaction_data(interaction_data) ==
               {"command",
                [
                  %{name: "option1", value: "value1", focused: false},
                  %{name: "option2", value: "value2", focused: false}
                ]}
    end

    test "parse interation data for component with custom_id" do
      interaction_data = %{
        custom_id: "command|option1:value1:option2:value2"
      }

      assert Helpers.parse_interaction_data(interaction_data) ==
               {"command",
                [
                  %{name: "option1", value: "value1", focused: false},
                  %{name: "option2", value: "value2", focused: false}
                ]}
    end
  end
end
