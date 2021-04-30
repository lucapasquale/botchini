defmodule BotchiniTest.Twitch.Routes.WebhookCallbackTest do
  use ExUnit.Case

  alias Botchini.Twitch.Routes.WebhookCallback

  describe "get_event_type" do
    test "get event for webhook confirmation" do
      body = %{
        "challenge" => "challenge",
        "subscription" => %{"status" => "webhook_callback_verification_pending"}
      }

      assert WebhookCallback.get_event_type(body) == {:confirm_subscription, "challenge"}
    end

    test "get event for stream.online" do
      body = %{
        "subscription" => %{"type" => "stream.online"}
      }

      assert WebhookCallback.get_event_type(body) == {:stream_online, body["subscription"]}
    end

    test "unknown if other type" do
      body = %{
        "subscription" => %{"type" => "OTHER_TYPE"}
      }

      assert WebhookCallback.get_event_type(body) == {:unknown, :invalid_event}
    end

    test "unknown if no type" do
      body = %{
        "subscription" => %{"type" => ""}
      }

      assert WebhookCallback.get_event_type(body) == {:unknown, :invalid_event}
    end
  end
end
