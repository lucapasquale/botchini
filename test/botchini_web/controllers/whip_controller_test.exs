defmodule BotchiniWebTest.WhipControllerTest do
  use BotchiniWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Ecto.Adapters.SQL.Sandbox
  alias ExWebRTC.{MediaStreamTrack, PeerConnection, SessionDescription}

  alias Botchini.{Repo, Screens}
  alias Botchini.Screens.Room

  @connect_timeout 5_000

  setup do
    :ok = Sandbox.checkout(Repo)

    on_exit(fn ->
      for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(Screens.RoomSupervisor) do
        DynamicSupervisor.terminate_child(Screens.RoomSupervisor, pid)
      end
    end)

    %{key: create_key("3")}
  end

  defp create_key(owner_id) do
    {:ok, key} =
      Screens.create_stream_key(%{
        guild_id: "1",
        owner_id: owner_id,
        channel_id: "2",
        owner_name: "Luca"
      })

    key
  end

  defp obs_offer do
    {:ok, pc} =
      PeerConnection.start_link(ice_servers: [], audio_codecs: [:opus], video_codecs: [:h264])

    for kind <- [:video, :audio] do
      {:ok, _transceiver} =
        PeerConnection.add_transceiver(pc, MediaStreamTrack.new(kind), direction: :sendonly)
    end

    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)
    assert_receive {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}}, @connect_timeout

    {pc, PeerConnection.get_local_description(pc).sdp}
  end

  defp whip(conn, key) do
    conn
    |> put_req_header("authorization", "Bearer #{key}")
    |> put_req_header("content-type", "application/sdp")
  end

  test "requires a valid stream key", %{conn: conn, key: key} do
    assert conn |> whip("wrong") |> post(~p"/api/whip", "v=0") |> response(401)

    assert build_conn()
           |> put_req_header("content-type", "application/sdp")
           |> post(~p"/api/whip", "v=0")
           |> response(401)

    create_key("3")
    assert build_conn() |> whip(key) |> post(~p"/api/whip", "v=0") |> response(401)
  end

  test "rejects invalid offers", %{conn: conn, key: key} do
    assert conn |> whip(key) |> post(~p"/api/whip", "garbage") |> response(400)
  end

  test "streams from OBS until it stops", %{conn: conn, key: key} do
    Screens.subscribe()
    {pc, offer} = obs_offer()

    conn = conn |> whip(key) |> post(~p"/api/whip", offer)

    assert answer = response(conn, 201)
    assert ["application/sdp"] = get_resp_header(conn, "content-type")
    assert answer =~ "a=candidate"
    assert answer =~ "H264"
    [location] = get_resp_header(conn, "location")

    :ok =
      PeerConnection.set_remote_description(pc, %SessionDescription{type: :answer, sdp: answer})

    assert_receive {:screen_room, :live, %Room{} = room}, @connect_timeout
    assert %Room{title: "Luca's stream", owner_id: "3", channel_id: "2"} = room

    path = URI.parse(location).path
    assert build_conn() |> whip(key) |> patch(path, "") |> response(405)
    assert build_conn() |> whip(create_key("4")) |> delete(path) |> response(404)
    assert build_conn() |> whip(key) |> delete(path) |> response(200)

    assert_receive {:screen_room, :ended, %Room{id: id}} when id == room.id
  end
end
