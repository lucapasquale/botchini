defmodule BotchiniWebTest.MusicControllerTest do
  use BotchiniWeb.ConnCase, async: false

  use Patch, alias: [patch: :patch_function]

  @moduletag :capture_log

  alias Botchini.Music.YtDlp
  alias Botchini.Screens.Jukebox
  alias BotchiniWeb.MusicController

  @audio "0123456789"

  setup %{conn: conn} do
    guild_id = "music-#{System.unique_integer([:positive])}"
    on_exit(fn -> Jukebox.stop(guild_id) end)

    patch_function(YtDlp, :lookup, fn term ->
      {:ok,
       %{
         id: "abcdefghijk",
         title: term,
         url: "https://youtu.be/abcdefghijk",
         thumbnail: "https://i.ytimg.com/vi/abcdefghijk/mqdefault.jpg",
         duration_ms: 180_000,
         channel: nil
       }}
    end)

    patch_function(YtDlp, :download, fn _url, dir, name ->
      path = Path.join(dir, "#{name}.m4a")
      File.write!(path, @audio)
      {:ok, path}
    end)

    :ok = Jukebox.add(guild_id, "one", %{id: "10", name: "Ana"})
    track_id = wait_for_download(guild_id)

    conn = init_test_session(conn, %{"discord_user_id" => "10", "discord_user_name" => "Ana"})

    %{conn: conn, path: ~p"/screens/#{guild_id}/music/#{track_id}", guild_id: guild_id}
  end

  defp wait_for_download(guild_id, attempts \\ 40) do
    case Jukebox.state(guild_id) do
      %{current: %{status: :ready, id: id}} ->
        id

      _loading when attempts > 0 ->
        Process.sleep(25)
        wait_for_download(guild_id, attempts - 1)
    end
  end

  test "serves the song's audio", %{conn: conn, path: path} do
    conn = get(conn, path)

    assert response(conn, 200) == @audio
    assert get_resp_header(conn, "content-type") == ["audio/mp4"]
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
  end

  test "serves parts of it, to start in the middle", %{conn: conn, path: path} do
    conn = conn |> put_req_header("range", "bytes=2-5") |> get(path)

    assert response(conn, 206) == "2345"
    assert get_resp_header(conn, "content-range") == ["bytes 2-5/10"]
  end

  test "refuses parts past the end", %{conn: conn, path: path} do
    conn = conn |> put_req_header("range", "bytes=20-") |> get(path)

    assert response(conn, 416) == ""
    assert get_resp_header(conn, "content-range") == ["bytes */10"]
  end

  test "needs a login", %{path: path} do
    conn = get(build_conn(), path)

    assert redirected_to(conn) =~ "/auth/login"
  end

  test "only serves songs of the guild they're in", %{conn: conn, path: path, guild_id: guild_id} do
    assert conn |> get(String.replace(path, guild_id, "1")) |> response(404)
    assert conn |> get(~p"/screens/#{guild_id}/music/unknown") |> response(404)
  end

  describe "parse_range/2" do
    test "reads the ranges browsers ask for" do
      assert MusicController.parse_range(["bytes=0-"], 10) == {:ok, 0, 9}
      assert MusicController.parse_range(["bytes=3-100"], 10) == {:ok, 3, 9}
      assert MusicController.parse_range(["bytes=-4"], 10) == {:ok, 6, 9}
      assert MusicController.parse_range(["bytes=-40"], 10) == {:ok, 0, 9}
      assert MusicController.parse_range(["bytes=0-1, 4-5"], 10) == :whole
      assert MusicController.parse_range([], 10) == :whole
      assert MusicController.parse_range(["bytes=5-2"], 10) == :unsatisfiable
      assert MusicController.parse_range(["bytes=10-"], 10) == :unsatisfiable
      assert MusicController.parse_range(["bytes=nope"], 10) == :unsatisfiable
    end
  end
end
