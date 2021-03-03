defmodule BotchiniTest.Routes.TwitchTest do
  use ExUnit.Case

  describe "get_event_type" do
    test "get event for webhook confirmation" do
      body = %{
        "challenge" => "challenge",
        "subscription" => %{"status" => "webhook_callback_verification_pending"}
      }

      assert Botchini.Routes.Twitch.get_event_type(body) == {:confirm_subscription, "challenge"}
    end

    test "get event for stream.online" do
      body = %{
        "subscription" => %{"type" => "stream.online"}
      }

      assert Botchini.Routes.Twitch.get_event_type(body) == {:stream_online, body["subscription"]}
    end

    test "unknown if other type" do
      body = %{
        "subscription" => %{"type" => "OTHER_TYPE"}
      }

      assert Botchini.Routes.Twitch.get_event_type(body) == {:unknown, :invalid_event}
    end

    test "unknown if no type" do
      body = %{
        "subscription" => %{"type" => ""}
      }

      assert Botchini.Routes.Twitch.get_event_type(body) == {:unknown, :invalid_event}
    end
  end
end
