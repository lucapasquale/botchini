defmodule BotchiniTest.Screens.RestreamTest do
  use ExUnit.Case, async: false

  use Patch

  @moduletag :capture_log

  alias Botchini.Music.YtDlp
  alias Botchini.Screens
  alias Botchini.Screens.{Activity, Restream, Room, TestBrowser}
  alias Botchini.Screens.Restream.Pipeline

  @ana %{id: "10", name: "Ana"}
  @bia %{id: "11", name: "Bia"}
  @url "https://www.youtube.com/watch?v=abcdefghijk"
  @connect_timeout 5_000

  # Every test gets a guild of its own. yt-dlp finds a 10 minute video titled
  # "Zoo", or a live stream, with new media links each time, and the pipeline is
  # a script that waits for the test to say how it ends, while the test sends the
  # packets ffmpeg would
  setup do
    guild_id = "restream-#{System.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), guild_id)
    File.mkdir_p!(dir)
    test = self()

    on_exit(fn ->
      Restream.stop(guild_id, @ana)
      File.rm_rf!(dir)
    end)

    patch(YtDlp, :lookup_stream, fn url, format ->
      media = ["https://media.example/#{System.unique_integer([:positive])}"]
      send(test, {:lookup, url, format, media})

      case url do
        "https://www.twitch.tv/offline" ->
          {:error, :stream_offline}

        "https://www.twitch.tv/" <> _ ->
          {:ok, %{title: "Zoo", url: url, live?: true, duration_ms: nil, media: media}}

        _video ->
          {:ok, %{title: "Zoo", url: url, live?: false, duration_ms: 600_000, media: media}}
      end
    end)

    patch(Pipeline, :open, fn media, video_port, audio_port, start_s ->
      send(test, {:pipeline, video_port, audio_port, start_s})
      send(test, {:pipeline_media, media})
      fake_pipeline(Path.join(dir, "end"))
    end)

    %{guild_id: guild_id, end_file: Path.join(dir, "end")}
  end

  # Prints what's in the file once it shows up, exiting with the code on its first
  # line, and removes it for the next pipeline. Like the real one, it kills its
  # session once the port closes
  defp fake_pipeline(end_file) do
    script = ~S"""
    exec 3<&0
    { cat >/dev/null; kill -TERM 0; } <&3 &
    while [ ! -f "$1" ]; do sleep 0.02; done
    trap '' TERM
    kill -TERM 0
    tail -n +2 "$1"
    status=$(head -n 1 "$1")
    rm -f "$1"
    exit "$status"
    """

    Port.open({:spawn_executable, System.find_executable("sh")}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args: ["-c", script, "fake-pipeline", end_file]
    ])
  end

  defp end_pipeline(end_file, code, output \\ "") do
    File.write!(end_file <> ".tmp", "#{code}\n#{output}")
    File.rename!(end_file <> ".tmp", end_file)
  end

  defp start(guild_id, url \\ @url) do
    assert Restream.start(guild_id, url, @ana) == :ok
    assert_receive {:pipeline, video_port, audio_port, 0}
    {video_port, audio_port}
  end

  # Started and sending, like once it's showing
  defp start_live(guild_id, url \\ @url) do
    Restream.subscribe(guild_id)
    {video_port, _audio_port} = start(guild_id, url)
    send_rtp(video_port, 1)
    assert_receive {:restream, {:state, %{status: :live}}}
  end

  defp pipeline_os_pid(guild_id) do
    %{port: port} = :sys.get_state(GenServer.whereis(restream(guild_id)))
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    os_pid
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

  describe "pausing and skipping" do
    test "pauses for everyone, and plays again where it was", %{guild_id: guild_id} do
      start_live(guild_id)
      os_pid = pipeline_os_pid(guild_id)
      Process.sleep(1_100)

      assert Restream.pause(guild_id, @bia) == :ok

      assert_receive {:restream,
                      {:state, %{status: :paused, paused_by: "Bia", position_ms: position}}}

      assert position >= 1_000
      # The room stays, showing the last picture
      assert %Room{live?: true} = link_room(guild_id)
      assert eventually(fn -> not alive?(os_pid) end)

      assert Restream.resume(guild_id) == :ok

      start_s = div(position, 1_000)
      assert_receive {:pipeline, video_port, _audio_port, ^start_s}
      assert_receive {:restream, {:state, %{status: :starting, paused_by: nil}}}

      send_rtp(video_port, 1)
      assert_receive {:restream, {:state, %{status: :live, position_ms: position}}}
      assert position == start_s * 1_000
    end

    test "skips through videos, which stay paused if they were", %{guild_id: guild_id} do
      start_live(guild_id)

      Restream.seek(guild_id, 125_500)
      assert_receive {:pipeline, _video_port, _audio_port, 125}
      assert_receive {:restream, {:state, %{status: :starting, position_ms: 125_000}}}

      Restream.pause(guild_id, @bia)
      Restream.seek(guild_id, 30_000)
      assert_receive {:restream, {:state, %{status: :paused, position_ms: 30_000}}}
      refute_receive {:pipeline, _video_port, _audio_port, _start_s}

      # Up to a second before the end
      Restream.seek(guild_id, 10_000_000)
      assert_receive {:restream, {:state, %{status: :paused, position_ms: 599_000}}}

      Restream.resume(guild_id)
      assert_receive {:pipeline, _video_port, _audio_port, 599}
    end

    test "plays live streams again from where they are now", %{guild_id: guild_id} do
      start_live(guild_id, "https://www.twitch.tv/someone")
      assert %{duration_ms: nil} = Restream.state(guild_id)

      Restream.seek(guild_id, 30_000)
      refute_receive {:pipeline, _video_port, _audio_port, _start_s}

      Restream.pause(guild_id, @bia)
      Restream.resume(guild_id)
      assert_receive {:pipeline, _video_port, _audio_port, 0}
    end

    test "waits until it's showing to be paused", %{guild_id: guild_id} do
      start(guild_id)

      assert Restream.pause(guild_id, @bia) == :ok
      assert Restream.resume(guild_id) == :ok

      assert %{status: :starting, paused_by: nil} = Restream.state(guild_id)
      refute_receive {:pipeline, _video_port, _audio_port, _start_s}
    end

    test "plays the media the lookup found, without looking it up again",
         %{guild_id: guild_id} do
      start_live(guild_id)
      assert_receive {:lookup, @url, format, media}
      assert format == Pipeline.format()
      assert_receive {:pipeline_media, ^media}

      Restream.pause(guild_id, @bia)
      Restream.resume(guild_id)
      Restream.seek(guild_id, 30_000)

      assert_receive {:pipeline_media, ^media}
      assert_receive {:pipeline_media, ^media}
      refute_receive {:lookup, _url, _format, _media}
    end

    test "looks the media up again once when it stops working",
         %{guild_id: guild_id, end_file: end_file} do
      start_live(guild_id)
      assert_receive {:lookup, _url, _format, expired}
      Restream.pause(guild_id, @bia)
      Restream.resume(guild_id)
      assert_receive {:pipeline, _video_port, _audio_port, _start_s}
      assert_receive {:pipeline_media, ^expired}

      end_pipeline(end_file, 1, "HTTP error 403 Forbidden")

      assert_receive {:lookup, @url, _format, media}
      assert_receive {:pipeline, video_port, _audio_port, _start_s}
      assert_receive {:pipeline_media, ^media}

      send_rtp(video_port, 1)
      assert_receive {:restream, {:state, %{status: :live}}}
    end

    test "ends when it can't play again, even with its media looked up again",
         %{guild_id: guild_id, end_file: end_file} do
      Activity.subscribe(guild_id)
      start_live(guild_id)
      Restream.pause(guild_id, @bia)
      Restream.resume(guild_id)
      assert_receive {:pipeline, _video_port, _audio_port, _start_s}

      end_pipeline(end_file, 1, "HTTP error 403 Forbidden")
      assert_receive {:pipeline, _video_port, _audio_port, _start_s}
      end_pipeline(end_file, 1, "HTTP error 403 Forbidden")

      assert_receive {:screen_activity,
                      %{kind: :stream_ended, detail: "the video stopped loading"}}

      assert_receive {:restream, {:state, nil}}
    end
  end

  describe "stopping" do
    test "stop/2 ends the room, saying who stopped it", %{guild_id: guild_id} do
      Activity.subscribe(guild_id)
      {video_port, _audio_port} = start(guild_id)
      send_rtp(video_port, 1)
      assert_receive {:screen_activity, %{kind: :stream_started}}

      assert Restream.stop(guild_id, @bia) == :ok

      assert_receive {:screen_activity,
                      %{kind: :stream_ended, actor: "Ana", detail: "stopped by Bia"}}

      assert Restream.state(guild_id) == nil
      assert link_room(guild_id) == nil
    end

    test "closing the room stops the video", %{guild_id: guild_id} do
      Restream.subscribe(guild_id)
      {video_port, _audio_port} = start(guild_id)
      send_rtp(video_port, 1)
      assert_receive {:restream, {:state, %{status: :live}}}

      os_pid = pipeline_os_pid(guild_id)

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
