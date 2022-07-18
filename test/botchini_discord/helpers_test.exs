defmodule BotchiniDiscordTest.HelpersTest do
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

      {"command",
       [
         %{name: "option1", value: "value1", focused: false},
         %{name: "option2", value: "value2", focused: false}
       ]} = Helpers.parse_interaction_data(interaction_data)
    end

    test "parse interation data for component with custom_id" do
      interaction_data = %{
        custom_id: "command|option1:value1:option2:value2"
      }

      {"command",
       [
         %{name: "option1", value: "value1", focused: false},
         %{name: "option2", value: "value2", focused: false}
       ]} = Helpers.parse_interaction_data(interaction_data)
    end
  end

  describe "get_option" do
    test "should get value and focused from options" do
      options = [
        %{name: "first", value: "first", focused: false},
        %{name: "second", value: "second", focused: false},
        %{name: "third", value: "third", focused: false}
      ]

      {"second", false} = Helpers.get_option(options, "second")
    end

    test "should raise if option not found" do
      options = [
        %{name: "first", value: "first", focused: false},
        %{name: "second", value: "second", focused: false},
        %{name: "third", value: "third", focused: false}
      ]

      assert_raise RuntimeError, "Invalid option received", fn ->
        Helpers.get_option(options, "invalid")
      end
    end

    test "should raise if options are empty" do
      assert_raise RuntimeError, "Invalid option received", fn ->
        Helpers.get_option([], "first")
      end
    end
  end
end
