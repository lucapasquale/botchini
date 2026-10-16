defmodule BotchiniTest.Screens.ClientStatsTest do
  use ExUnit.Case, async: false

  alias Botchini.Screens.ClientStats

  @events [
    [:botchini, :screens, :viewer, :video],
    [:botchini, :screens, :viewer, :audio],
    [:botchini, :screens, :broadcaster, :video],
    [:botchini, :screens, :broadcaster, :audio]
  ]

  setup do
    test = self()
    handler_id = "client-stats-test-#{inspect(test)}"

    :telemetry.attach_many(
      handler_id,
      @events,
      fn event, measurements, metadata, _config ->
        send(test, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  describe "viewer/2" do
    test "keeps the numbers in sensible ranges, by source and stereo" do
      ClientStats.viewer(:tab, %{
        "video" => %{
          "kbps" => 2_500.5,
          "fps" => 30,
          "frames_dropped_percent" => 140,
          "jitter_ms" => -3,
          "height" => "720",
          "made_up" => 1
        },
        "audio" => %{"kbps" => 128, "concealed_percent" => 0.5, "stereo" => true}
      })

      assert_receive {:telemetry, [:botchini, :screens, :viewer, :video], video, %{source: "tab"}}

      assert video == %{kbps: 2_500.5, fps: 30}

      assert_receive {:telemetry, [:botchini, :screens, :viewer, :audio], audio,
                      %{source: "tab", stereo: "true"}}

      assert audio == %{kbps: 128, concealed_percent: 0.5}
    end

    test "tells mono audio and unknown sources apart" do
      ClientStats.viewer(nil, %{"audio" => %{"kbps" => 64}})
      ClientStats.viewer(:link, %{"audio" => %{"kbps" => 64, "stereo" => "yes"}})

      assert_receive {:telemetry, _event, _audio, %{source: "unknown", stereo: "false"}}
      assert_receive {:telemetry, _event, _audio, %{source: "other", stereo: "false"}}
    end

    test "says nothing without numbers" do
      ClientStats.viewer(:screen, %{"video" => "lots", "audio" => %{"kbps" => nil}})
      refute_receive {:telemetry, _event, _measurements, _metadata}
    end
  end

  describe "broadcaster/2" do
    test "tells why the browser holds back quality" do
      ClientStats.broadcaster(:tab, %{
        "video" => %{"kbps" => 8_000, "rtt_ms" => 20},
        "audio" => %{"kbps" => 128},
        "quality_limitation" => "bandwidth"
      })

      ClientStats.broadcaster(:obs, %{
        "video" => %{"fps" => 60},
        "quality_limitation" => "aliens"
      })

      assert_receive {:telemetry, [:botchini, :screens, :broadcaster, :video],
                      %{kbps: 8_000, rtt_ms: 20},
                      %{source: "tab", quality_limitation: "bandwidth"}}

      assert_receive {:telemetry, [:botchini, :screens, :broadcaster, :audio], %{kbps: 128},
                      %{source: "tab"}}

      assert_receive {:telemetry, [:botchini, :screens, :broadcaster, :video], %{fps: 60},
                      %{source: "obs", quality_limitation: "other"}}
    end
  end

  test "due/3 lets a page report once every 5 seconds per screen" do
    assert {:ok, reported} = ClientStats.due(%{}, "a", 0)
    assert ClientStats.due(reported, "a", 4_999) == :too_soon
    assert {:ok, reported} = ClientStats.due(reported, "b", 4_999)
    assert {:ok, %{"a" => 5_000}} = ClientStats.due(reported, "a", 5_000)
  end
end
