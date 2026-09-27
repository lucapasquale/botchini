defmodule BotchiniTest.Services.TelemetryTest do
  use ExUnit.Case, async: false

  alias Botchini.Services.Telemetry

  setup do
    test_pid = self()
    handler_id = "telemetry-test-#{inspect(test_pid)}"

    :telemetry.attach(
      handler_id,
      [:botchini, :http, :request, :stop],
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:http_request, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  test "emits the service, endpoint and status of a response" do
    Req.new(base_url: "http://api.test", plug: &Plug.Conn.send_resp(&1, 200, "ok"))
    |> Telemetry.attach(:youtube)
    |> Req.get!(url: "/youtube/v3/videos")

    assert_received {:http_request, %{duration: duration},
                     %{
                       service: :youtube,
                       endpoint: "/youtube/v3/videos",
                       status: "200",
                       result: :ok
                     }}

    assert is_integer(duration)
  end

  test "marks error responses as errors" do
    Req.new(url: "http://api.test/helix/users", plug: &Plug.Conn.send_resp(&1, 404, ""))
    |> Telemetry.attach(:twitch)
    |> Req.get!()

    assert_received {:http_request, _measurements, %{status: "404", result: :error}}
  end

  test "marks transport errors as errors" do
    {:error, _exception} =
      Req.new(url: "http://127.0.0.1:1/helix/users", retry: false)
      |> Telemetry.attach(:twitch)
      |> Req.get()

    assert_received {:http_request, _measurements,
                     %{service: :twitch, status: "transport_error", result: :error}}
  end
end
