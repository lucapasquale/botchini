defmodule BotchiniTest.Music.PlaybackFailureTest do
  use ExUnit.Case, async: true

  alias Botchini.Music.PlaybackFailure

  describe "classify" do
    test "detects age restricted videos" do
      output =
        "ERROR: [youtube] gs-KGzm8rZs: Sign in to confirm your age. Use --cookies-from-browser"

      assert PlaybackFailure.classify(output) ==
               {:age_restricted,
                "[youtube] gs-KGzm8rZs: Sign in to confirm your age. Use --cookies-from-browser"}
    end

    test "detects YouTube bot checks" do
      output = "ERROR: [youtube] abc: Sign in to confirm you’re not a bot. Use --cookies"

      assert {:bot_check, _error} = PlaybackFailure.classify(output)
    end

    test "detects blocked downloads" do
      output = "ERROR: unable to download video data: HTTP Error 403: Forbidden"

      assert {:forbidden, "unable to download video data: HTTP Error 403: Forbidden"} =
               PlaybackFailure.classify(output)
    end

    test "detects unavailable videos" do
      output = "ERROR: [youtube] aaaaaaaaaaa: This video is unavailable"

      assert {:unavailable, "[youtube] aaaaaaaaaaa: This video is unavailable"} =
               PlaybackFailure.classify(output)
    end

    test "detects offline streams from streamlink json output" do
      output = """
      {
        "error": "No playable streams found on this URL: https://www.twitch.tv/someone"
      }
      """

      assert {:stream_offline,
              "No playable streams found on this URL: https://www.twitch.tv/someone"} =
               PlaybackFailure.classify(output)
    end

    test "falls back to unknown with the first line as the error" do
      assert PlaybackFailure.classify("something odd happened\nmore details") ==
               {:unknown, "something odd happened"}
    end
  end
end
