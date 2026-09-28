defmodule BotchiniTest.ScreensTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Botchini.Screens
  alias Botchini.Screens.{Room, TestBrowser}

  # ICE over localhost is quick, but DTLS handshakes can take a moment on busy CI machines
  @connect_timeout 5_000

  setup do
    config = Application.get_env(:botchini, Screens)

    on_exit(fn ->
      Application.put_env(:botchini, Screens, config)

      for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(Screens.RoomSupervisor) do
        DynamicSupervisor.terminate_child(Screens.RoomSupervisor, pid)
      end
    end)
  end

  defp put_config(changes) do
    Application.put_env(
      :botchini,
      Screens,
      Keyword.merge(Application.get_env(:botchini, Screens), changes)
    )
  end

  defp start_room(attrs \\ %{}) do
    {:ok, room} =
      Map.merge(
        %{
          title: "Elden Ring",
          guild_id: "1",
          channel_id: "2",
          owner_id: "3",
          owner_name: "Luca"
        },
        attrs
      )
      |> Screens.start_room()

    room
  end

  # Starting with the first frame of a VP8 keyframe, as the payload has to parse
  defp vp8_packet(sequence_number) do
    ExRTP.Packet.new(<<0x10, 0x9D, 0x01, 0x2A, sequence_number::32>>,
      sequence_number: sequence_number,
      timestamp: sequence_number * 3_000
    )
  end

  # The viewer can report connected a moment before the room does, so the
  # broadcaster keeps sending until a packet arrives
  defp send_until_received(publisher, viewer, first_sequence_number) do
    Enum.reduce_while(first_sequence_number..(first_sequence_number + 50), nil, fn sn, nil ->
      TestBrowser.send_rtp(publisher, :video, vp8_packet(sn))

      receive do
        {:browser, ^viewer, {:rtp, :video, packet}} -> {:halt, packet}
      after
        100 -> {:cont, nil}
      end
    end) || flunk("viewer never received the broadcast")
  end

  defp flush_room_events do
    receive do
      {:screen_room, _event, _room} -> flush_room_events()
    after
      0 -> :ok
    end
  end

  defp connect(room, role) do
    {:ok, browser} = TestBrowser.start_link(room.id, role)
    assert_receive {:browser, ^browser, {:connection_state, :connected}}, @connect_timeout
    browser
  end

  describe "start_room/1" do
    test "starts a room with unguessable ids" do
      room = start_room()

      assert %Room{title: "Elden Ring", live?: false, viewer_count: 0} = room
      assert byte_size(room.id) >= 22
      assert byte_size(room.broadcast_key) >= 22
      assert room.id != room.broadcast_key
      assert Screens.get_room(room.id) == room
    end

    test "returns the owner's running room instead of starting another" do
      room = start_room()

      assert start_room(%{title: "Another game"}) == room
      assert start_room(%{guild_id: "10"}).id != room.id
    end
  end

  test "list_rooms/1 only lists the guild's rooms" do
    room = start_room()
    other_room = start_room(%{owner_id: "4"})
    start_room(%{guild_id: "10"})

    assert "1" |> Screens.list_rooms() |> Enum.map(& &1.id) |> Enum.sort() ==
             Enum.sort([room.id, other_room.id])
  end

  test "get_room_for_broadcast/2 requires the room's broadcast key" do
    room = start_room()

    assert Screens.get_room_for_broadcast(room.id, room.broadcast_key) == room
    assert Screens.get_room_for_broadcast(room.id, "wrong key") == nil
    assert Screens.get_room_for_broadcast(room.id, nil) == nil
    assert Screens.get_room_for_broadcast("unknown", room.broadcast_key) == nil
  end

  test "stop_room/2 ends the room and notifies subscribers" do
    room = start_room()
    Screens.subscribe()

    assert Screens.stop_room(room) == :ok
    assert_receive {:screen_room, :ended, %Room{id: id}} when id == room.id
    assert Screens.get_room(room.id) == nil
    assert Screens.stop_room(room) == {:error, :not_found}
  end

  test "ends rooms nobody starts broadcasting to" do
    put_config(start_timeout_ms: 50)
    room = start_room()
    Screens.subscribe(room.id)

    assert_receive {:screen_room, :ended, _room}, 1_000
  end

  test "rejects invalid offers" do
    room = start_room()

    assert Room.publish(room.id, %{"type" => "answer", "sdp" => ""}) == {:error, :invalid_offer}
    assert Room.watch(room.id, "not an offer") == {:error, :invalid_offer}
    assert Room.publish("unknown", %{}) == {:error, :not_found}
  end

  test "survives malformed offers from anyone with the link" do
    room = start_room()

    for sdp <- [
          "garbage",
          "v=0\r\n",
          "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n"
        ] do
      assert {:error, _reason} = Room.watch(room.id, %{"type" => "offer", "sdp" => sdp})
      assert {:error, _reason} = Room.publish(room.id, %{"type" => "offer", "sdp" => sdp})
    end

    assert Screens.get_room(room.id)
  end

  test "rejects viewers once the room is full" do
    put_config(max_viewers: 0)
    room = start_room()

    assert Room.watch(room.id, %{}) == {:error, :full}
  end

  describe "streaming" do
    test "forwards the broadcaster's media to viewers" do
      room = start_room()
      Screens.subscribe(room.id)

      publisher = connect(room, :publisher)
      assert_receive {:screen_room, :live, %Room{live?: true}}
      # Keyframes can only be requested once the room knows the stream's SSRC
      TestBrowser.send_rtp(publisher, :video, vp8_packet(99))

      viewer = connect(room, :viewer)
      assert_receive {:screen_room, :updated, %Room{viewer_count: 1}}, @connect_timeout
      # Viewers can only start decoding from a keyframe
      assert_receive {:browser, ^publisher, :keyframe_request}, @connect_timeout

      packet = send_until_received(publisher, viewer, 100)
      assert <<0x10, 0x9D, 0x01, 0x2A, _sequence_number::32>> = packet.payload
    end

    test "forwards the broadcaster's audio too" do
      room = start_room()
      viewer = connect(room, :viewer)
      publisher = connect(room, :publisher)
      send_until_received(publisher, viewer, 100)

      TestBrowser.send_rtp(
        publisher,
        :audio,
        ExRTP.Packet.new(<<0xFC, 0xFF, 0xFE>>, sequence_number: 1)
      )

      assert_receive {:browser, ^viewer, {:rtp, :audio, packet}}, 1_000
      assert packet.payload == <<0xFC, 0xFF, 0xFE>>
    end

    test "reports rooms going live once, and viewers joining" do
      test_pid = self()
      handler_id = "screens-test-#{inspect(test_pid)}"

      :telemetry.attach_many(
        handler_id,
        [[:botchini, :screens, :room, :live], [:botchini, :screens, :viewer, :join]],
        fn event, _measurements, _metadata, _config -> send(test_pid, {:telemetry, event}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      room = start_room()

      connect(room, :publisher)
      assert_receive {:telemetry, [:botchini, :screens, :room, :live]}, @connect_timeout

      connect(room, :viewer)
      assert_receive {:telemetry, [:botchini, :screens, :viewer, :join]}, @connect_timeout

      # A refreshed broadcaster tab is the same screen share, not a new one
      connect(room, :publisher)
      refute_receive {:telemetry, [:botchini, :screens, :room, :live]}, 500
    end

    test "viewers can join before the broadcaster" do
      room = start_room()

      viewer = connect(room, :viewer)
      publisher = connect(room, :publisher)

      assert send_until_received(publisher, viewer, 100)
    end

    test "keeps the stream continuous when the broadcaster reconnects" do
      room = start_room()
      Screens.subscribe(room.id)

      publisher = connect(room, :publisher)
      assert_receive {:screen_room, :live, _room}
      viewer = connect(room, :viewer)
      first = send_until_received(publisher, viewer, 100)

      # A refreshed tab starts a new stream, with unrelated sequence numbers
      flush_room_events()
      new_publisher = connect(room, :publisher)
      assert_receive {:screen_room, :updated, %Room{live?: false}}
      assert_receive {:screen_room, :updated, %Room{live?: true}}, @connect_timeout
      refute_received {:screen_room, :live, _room}

      TestBrowser.send_rtp(new_publisher, :video, vp8_packet(50_000))
      assert_receive {:browser, ^viewer, {:rtp, :video, packet}}, 1_000

      assert packet.sequence_number > first.sequence_number
      assert packet.sequence_number < first.sequence_number + 100
    end

    test "drops viewers whose page closed" do
      room = start_room()
      Screens.subscribe(room.id)

      viewer = connect(room, :viewer)
      assert_receive {:screen_room, :updated, %Room{viewer_count: 1}}, @connect_timeout

      TestBrowser.close(viewer)
      assert_receive {:screen_room, :updated, %Room{viewer_count: 0}}, 1_000
    end

    test "ends the room when the broadcaster doesn't come back" do
      put_config(reconnect_timeout_ms: 100)
      room = start_room()
      Screens.subscribe(room.id)

      publisher = connect(room, :publisher)
      assert_receive {:screen_room, :live, _room}

      TestBrowser.close(publisher)
      assert_receive {:screen_room, :updated, %Room{live?: false}}, 1_000
      assert_receive {:screen_room, :ended, _room}, 1_000
    end
  end
end
