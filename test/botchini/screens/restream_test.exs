defmodule BotchiniTest.Screens.RestreamTest do
  use ExUnit.Case, async: false

  use Patch

  @moduletag :capture_log

  alias Botchini.Music.YtDlp
  alias Botchini.Screens
  alias Botchini.Screens.{Activity, Restream, Room, TestBrowser}
  alias Botchini.Screens.Restream.Pipeline

  @ana %{id: "10", name: "Ana"}
  @url "https://www.youtube.com/watch?v=abcdefghijk"
  @connect_timeout 5_000

  # Every test gets a guild of its own. yt-dlp finds a video titled "Zoo", and
  # the pipeline is a script that waits for the test to say how it ends, while
  # the test sends the packets ffmpeg would
  setup do
    guild_id = "restream-#{System.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), guild_id)
    File.mkdir_p!(dir)
    test = self()

    on_exit(fn ->
      Restream.stop(guild_id)
      File.rm_rf!(dir)
    end)

    patch(YtDlp, :lookup_stream, fn
      "https://www.twitch.tv/offline" -> {:error, :stream_offline}
      url -> {:ok, %{title: "Zoo", url: url, live?: false}}
    end)

    patch(Pipeline, :open, fn _url, video_port, audio_port ->
      send(test, {:pipeline, video_port, audio_port})
      fake_pipeline(Path.join(dir, "end"))
    end)

    %{guild_id: guild_id, end_file: Path.join(dir, "end")}
  end

  # Prints what's in the file once it shows up, exiting with the code on its first
  # line. It runs in a session of its own like the real one, which closing kills
  defp fake_pipeline(end_file) do
    script = ~S"""
    while [ ! -f "$1" ]; do sleep 0.02; done
    tail -n +2 "$1"
    exit "$(head -n 1 "$1")"
    """

    Port.open({:spawn_executable, System.find_executable("setsid")}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args: ["sh", "-c", script, "fake-pipeline", end_file]
    ])
  end

  defp end_pipeline(end_file, code, output \\ "") do
    File.write!(end_file <> ".tmp", "#{code}\n#{output}")
    File.rename!(end_file <> ".tmp", end_file)
  end

  defp start(guild_id, url \\ @url) do
    assert Restream.start(guild_id, url, @ana) == :ok
    assert_receive {:pipeline, video_port, audio_port}
    {video_port, audio_port}
  end

  defp send_rtp(port, sequence_number) do
    {:ok, socket} = :gen_udp.open(0, [:binary])

    packet =
      <<0x65, sequence_number::32>>
      |> ExRTP.Packet.new(
        payload_type: 96,
        sequence_number: sequence_number,
        timestamp: sequence_number * 3_000,
        ssrc: 1234
      )
      |> ExRTP.Packet.encode()

    :ok = :gen_udp.send(socket, {127, 0, 0, 1}, port, packet)
    :gen_udp.close(socket)
  end

  defp link_room(guild_id) do
    Enum.find(Screens.list_rooms(guild_id), &(&1.source == :link))
  end

  defp eventually(fun, attempts \\ 50) do
    case fun.() do
      result when result in [nil, false] and attempts > 0 ->
        Process.sleep(20)
        eventually(fun, attempts - 1)

      result ->
        result
    end
  end

  describe "start/3" do
    test "only takes YouTube and Twitch links", %{guild_id: guild_id} do
      assert Restream.start(guild_id, "  ", @ana) == {:error, :blank}

      for url <- [
            "https://example.com/video.mp4",
            "file:///etc/passwd",
            "zoo",
            "ftp://youtube.com"
          ] do
        assert Restream.start(guild_id, url, @ana) == {:error, :unsupported_url}
      end

      assert Restream.state(guild_id) == nil
    end

    test "shows one video at a time", %{guild_id: guild_id} do
      start(guild_id)

      assert Restream.start(guild_id, "https://www.twitch.tv/someone", @ana) ==
               {:error, :already_showing}
    end

    test "tells the admin when the link can't be shown", %{guild_id: guild_id} do
      assert Restream.start(guild_id, "https://www.twitch.tv/offline", @ana) == :ok

      assert_receive {:restream, {:failed, :stream_offline}}
      assert eventually(fn -> Restream.state(guild_id) == nil end)
      assert link_room(guild_id) == nil
    end
  end

  describe "showing a video" do
    test "goes live as a room with the video's title once packets come", %{guild_id: guild_id} do
      Restream.subscribe(guild_id)
      Screens.subscribe_guild(guild_id)
      {video_port, _audio_port} = start(guild_id)

      assert_receive {:restream, {:state, %{status: :starting, title: "Zoo", added_by: "Ana"}}}
      assert %Room{live?: false, title: "Zoo", owner_id: "10"} = link_room(guild_id)

      send_rtp(video_port, 1)

      assert_receive {:restream, {:state, %{status: :live}}}
      assert_receive {:screen_room, :live, %Room{source: :link, title: "Zoo"}}
    end

    test "forwards the video to viewers", %{guild_id: guild_id} do
      {video_port, _audio_port} = start(guild_id)
      room = eventually(fn -> link_room(guild_id) end)

      {:ok, viewer} = TestBrowser.start_link(room.id, :viewer)
      assert_receive {:browser, ^viewer, {:connection_state, :connected}}, @connect_timeout

      packet =
        Enum.find_value(1..50, fn sequence_number ->
          send_rtp(video_port, sequence_number)

          receive do
            {:browser, ^viewer, {:rtp, :video, packet}} -> packet
          after
            100 -> nil
          end
        end) || flunk("viewer never received the video")

      assert <<0x65, _sequence_number::32>> = packet.payload
    end

    test "doesn't count as the admin's own screen share", %{guild_id: guild_id} do
      start(guild_id)
      eventually(fn -> link_room(guild_id) end)

      assert Screens.find_owner_room(guild_id, @ana.id) == nil

      {:ok, own} =
        Screens.start_room(%{
          title: "Ana's screen",
          guild_id: guild_id,
          channel_id: nil,
          owner_id: @ana.id,
          owner_name: @ana.name
        })

      assert own.source == nil
      Screens.stop_room(own)
    end

    test "ends the room when the video ends", %{guild_id: guild_id, end_file: end_file} do
      Activity.subscribe(guild_id)
      Restream.subscribe(guild_id)
      {video_port, _audio_port} = start(guild_id)
      send_rtp(video_port, 1)
      assert_receive {:screen_activity, %{kind: :stream_started, actor: "Ana", detail: "Zoo"}}

      end_pipeline(end_file, 0)

      assert_receive {:screen_activity,
                      %{kind: :stream_ended, actor: "Ana", detail: "the video ended"}}

      assert_receive {:restream, {:state, nil}}
      assert link_room(guild_id) == nil
    end

    test "tells the admin why it couldn't start", %{guild_id: guild_id, end_file: end_file} do
      Activity.subscribe(guild_id)
      start(guild_id)

      end_pipeline(end_file, 1, "ERROR: [youtube] abcdefghijk: Video unavailable")

      assert_receive {:restream, {:failed, :unavailable}}
      assert eventually(fn -> link_room(guild_id) == nil end)
      # Nothing was shown, so nothing happened
      refute_receive {:screen_activity, _event}, 200
    end
  end

  describe "stopping" do
    test "stop/1 ends the room", %{guild_id: guild_id} do
      Activity.subscribe(guild_id)
      {video_port, _audio_port} = start(guild_id)
      send_rtp(video_port, 1)
      assert_receive {:screen_activity, %{kind: :stream_started}}

      assert Restream.stop(guild_id) == :ok

      assert_receive {:screen_activity, %{kind: :stream_ended, detail: "closed by an admin"}}
      assert Restream.state(guild_id) == nil
      assert link_room(guild_id) == nil
    end

    test "closing the room stops the video", %{guild_id: guild_id} do
      Restream.subscribe(guild_id)
      {video_port, _audio_port} = start(guild_id)
      send_rtp(video_port, 1)
      assert_receive {:restream, {:state, %{status: :live}}}

      %{port: port} = :sys.get_state(GenServer.whereis(restream(guild_id)))
      {:os_pid, os_pid} = Port.info(port, :os_pid)

      Screens.stop_room(link_room(guild_id), :closed_by_admin)

      assert_receive {:restream, {:state, nil}}
      # The fake pipeline is killed, as the real one would be
      assert eventually(fn -> not alive?(os_pid) end)
    end
  end

  defp restream(guild_id), do: {:via, Registry, {Screens.RestreamRegistry, guild_id}}

  defp alive?(os_pid),
    do: match?({_output, 0}, System.cmd("kill", ["-0", "#{os_pid}"], stderr_to_stdout: true))
end
