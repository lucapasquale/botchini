defmodule BotchiniTest.Music.YtDlpTest do
  use ExUnit.Case, async: true

  alias Botchini.Music.YtDlp

  describe "lookup/1" do
    # These never reach yt-dlp, so members can't have the server fetch other sites
    test "only takes YouTube links" do
      assert YtDlp.lookup("https://example.com/song.mp3") == {:error, :unsupported_url}
      assert YtDlp.lookup("http://localhost:4000/admin") == {:error, :unsupported_url}
    end
  end

  describe "youtube_url?/1" do
    test "knows YouTube's addresses" do
      assert YtDlp.youtube_url?("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      assert YtDlp.youtube_url?("https://youtu.be/dQw4w9WgXcQ")
      assert YtDlp.youtube_url?("https://music.youtube.com/watch?v=dQw4w9WgXcQ")
      refute YtDlp.youtube_url?("https://youtube.com.example.com/watch?v=dQw4w9WgXcQ")
      refute YtDlp.youtube_url?("never gonna give you up")
    end
  end
end
