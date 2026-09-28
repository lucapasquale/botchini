defmodule Botchini.Screens.TestBrowser do
  @moduledoc """
  Plays a browser tab in screen sharing tests: both its WebRTC peer and the
  LiveView relaying the signaling to the room. Reports what the peer sees to
  the test process as `{:browser, pid, event}` messages
  """

  use GenServer

  alias ExRTCP.Packet.PayloadFeedback.PLI
  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}

  alias Botchini.Screens.Room

  @typedoc """
  `:publisher` is a browser that can only send VP8, and `:h264_publisher` one
  that can send both, listing VP8 first like Chrome does
  """
  @type role :: :publisher | :h264_publisher | :whip_publisher | :viewer

  @spec start_link(String.t(), role()) :: GenServer.on_start()
  def start_link(room_id, role), do: GenServer.start_link(__MODULE__, {room_id, role, self()})

  @spec send_rtp(pid(), :video | :audio, ExRTP.Packet.t()) :: :ok
  def send_rtp(browser, kind, packet), do: GenServer.cast(browser, {:send_rtp, kind, packet})

  @spec close(pid()) :: :ok
  def close(browser), do: GenServer.stop(browser)

  @impl true
  def init({room_id, role, test_pid}) do
    {:ok, pc} =
      PeerConnection.start_link(
        ice_servers: [],
        audio_codecs: [:opus],
        video_codecs: video_codecs(role)
      )

    tracks = add_transceivers(pc, role)
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)
    :ok = connect(role, room_id, pc, offer)

    {:ok, %{room_id: room_id, pc: pc, role: role, test_pid: test_pid, tracks: tracks}}
  end

  defp video_codecs(:publisher), do: [:vp8]
  defp video_codecs(:h264_publisher), do: [:vp8, :h264]
  defp video_codecs(:whip_publisher), do: [:h264]
  defp video_codecs(:viewer), do: [:vp8, :h264]

  defp connect(:whip_publisher, room_id, pc, _offer) do
    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    end

    {:ok, answer, _session_id} =
      Room.publish_whip(room_id, PeerConnection.get_local_description(pc).sdp)

    PeerConnection.set_remote_description(pc, %SessionDescription{type: :answer, sdp: answer})
  end

  defp connect(role, room_id, pc, offer) do
    connect = if role == :viewer, do: &Room.watch/2, else: &Room.publish/2
    {:ok, answer} = connect.(room_id, SessionDescription.to_json(offer))
    PeerConnection.set_remote_description(pc, SessionDescription.from_json(answer))
  end

  # Publishers map kind => outbound track id, viewers map inbound track id => kind
  defp add_transceivers(pc, role) when role in [:publisher, :h264_publisher, :whip_publisher] do
    Map.new([:video, :audio], fn kind ->
      track = MediaStreamTrack.new(kind)
      {:ok, _transceiver} = PeerConnection.add_transceiver(pc, track, direction: :sendonly)
      {kind, track.id}
    end)
  end

  defp add_transceivers(pc, :viewer) do
    for kind <- [:video, :audio] do
      {:ok, _transceiver} = PeerConnection.add_transceiver(pc, kind, direction: :recvonly)
    end

    %{}
  end

  @impl true
  def handle_cast({:send_rtp, kind, packet}, state) do
    PeerConnection.send_rtp(state.pc, state.tracks[kind], packet)
    {:noreply, state}
  end

  @impl true
  def handle_info({:screens, _room_id, :reconnect}, state) do
    report(state, :reconnect)
    {:noreply, state}
  end

  def handle_info({:screens, _room_id, {:ice_candidate, candidate}}, state) do
    PeerConnection.add_ice_candidate(state.pc, ICECandidate.from_json(candidate))
    {:noreply, state}
  end

  def handle_info(
        {:ex_webrtc, _pc, {:ice_candidate, _candidate}},
        %{role: :whip_publisher} = state
      ),
      do: {:noreply, state}

  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, state) do
    Room.add_ice_candidate(state.room_id, ICECandidate.to_json(candidate))
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _pc, {:connection_state_change, conn_state}}, state) do
    report(state, {:connection_state, conn_state})
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _pc, {:track, track}}, state) do
    {:noreply, put_in(state, [:tracks, track.id], track.kind)}
  end

  def handle_info({:ex_webrtc, _pc, {:rtp, track_id, _rid, packet}}, state) do
    report(state, {:rtp, state.tracks[track_id], packet})
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _pc, {:rtcp, packets}}, state) do
    if Enum.any?(packets, &match?({_track_id, %PLI{}}, &1)), do: report(state, :keyframe_request)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp report(state, event), do: send(state.test_pid, {:browser, self(), event})
end
