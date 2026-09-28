defmodule Botchini.Screens.Room do
  @moduledoc """
  A screen sharing session: one broadcaster sending its screen over WebRTC, and
  the viewers it gets forwarded to (a tiny SFU).

  The room owns every PeerConnection, so the LiveViews only relay signaling
  between the browsers and this process. Each LiveView talks to the room with
  its own pid, and is monitored so closing the tab drops its connection.
  """

  use GenServer, restart: :temporary

  require Logger

  alias ExRTCP.Packet.PayloadFeedback.PLI
  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}
  alias ExWebRTC.RTP.Munger

  alias Botchini.Screens

  @type t :: %__MODULE__{
          id: String.t(),
          broadcast_key: String.t(),
          title: String.t(),
          guild_id: String.t(),
          channel_id: String.t(),
          owner_id: String.t(),
          owner_name: String.t(),
          started_at: DateTime.t(),
          live?: boolean(),
          viewer_count: non_neg_integer()
        }

  @enforce_keys [:id, :broadcast_key, :title, :guild_id, :channel_id, :owner_id, :owner_name]
  defstruct @enforce_keys ++ [:started_at, live?: false, viewer_count: 0]

  # Keyframes are expensive for the broadcaster, so viewers joining or
  # recovering from packet loss at the same time share a single request
  @keyframe_interval_ms 500

  @spec start_link(t()) :: GenServer.on_start()
  def start_link(%__MODULE__{} = room) do
    GenServer.start_link(__MODULE__, room, name: via(room))
  end

  @doc """
  Connects the calling process as the broadcaster, answering its SDP offer.
  A room has a single broadcaster, so this replaces any previous one (e.g. a refreshed tab)
  """
  @spec publish(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def publish(room_id, offer), do: call(room_id, {:publish, self(), offer})

  @doc """
  Connects the calling process as a viewer, answering its SDP offer
  """
  @spec watch(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def watch(room_id, offer), do: call(room_id, {:watch, self(), offer})

  @doc """
  Adds an ICE candidate trickled by the browser of the calling process
  """
  @spec add_ice_candidate(String.t(), map()) :: :ok
  def add_ice_candidate(room_id, candidate) do
    GenServer.cast(via(room_id), {:ice_candidate, self(), candidate})
  end

  @spec info(String.t()) :: {:ok, t()} | {:error, :not_found}
  def info(room_id), do: call(room_id, :info)

  @spec stop(String.t(), atom()) :: :ok | {:error, :not_found}
  def stop(room_id, reason) do
    case call(room_id, {:stop, reason}) do
      {:error, :not_found} -> {:error, :not_found}
      _ -> :ok
    end
  end

  defp call(room_id, message) do
    GenServer.call(via(room_id), message)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
    :exit, {:normal, _} -> {:error, :not_found}
  end

  defp via(%__MODULE__{} = room),
    do: {:via, Registry, {Screens.Registry, room.id, {room.guild_id, room.owner_id}}}

  defp via(room_id), do: {:via, Registry, {Screens.Registry, room_id}}

  ## Callbacks

  @impl true
  def init(room) do
    Process.flag(:trap_exit, true)
    Logger.metadata(screen_room_id: room.id, guild_id: room.guild_id)

    config = Screens.config()
    Process.send_after(self(), :max_duration, config[:max_duration_ms])

    state =
      %{
        room: %{room | started_at: DateTime.utc_now()},
        started_at: System.monotonic_time(),
        config: config,
        # pc pid => peer map, see new_peer/3
        peers: %{},
        # LiveView pid => pc pid, to route the ICE candidates each browser sends
        lv_peers: %{},
        publisher: nil,
        # The room is announced once, reconnecting broadcasters only update it
        went_live?: false,
        # One munger per track kind keeps sequence numbers and timestamps
        # continuous for viewers when the broadcaster reconnects
        mungers: %{video: Munger.new(:vp8, 90_000), audio: Munger.new(:opus, 48_000)},
        last_keyframe_request: nil,
        idle_timer: nil,
        peak_viewers: 0,
        end_reason: :shutdown
      }
      |> schedule_idle_timeout(config[:start_timeout_ms])

    :telemetry.execute([:botchini, :screens, :room, :start], %{count: 1}, %{})
    Logger.info("Screen room started", event: "screen_room_started")

    {:ok, state}
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, {:ok, state.room}, state}

  def handle_call({:stop, reason}, _from, state) do
    {:stop, :normal, :ok, %{state | end_reason: reason}}
  end

  def handle_call({:publish, lv, offer}, _from, state) do
    state =
      state
      |> drop_lv_peer(lv)
      |> drop_publisher()

    case negotiate(state, offer, fn _pc -> :ok end) do
      {:ok, pc, answer} ->
        state =
          state
          |> put_peer(pc, new_peer(:publisher, lv, %{}))
          |> Map.put(:publisher, pc)
          |> update_in([:mungers], &Map.new(&1, fn {kind, m} -> {kind, Munger.update(m)} end))

        {:reply, {:ok, answer}, state}

      {:error, reason} ->
        Logger.warning("Failed to connect screen broadcaster", reason: inspect(reason))
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:watch, lv, offer}, _from, state) do
    state = drop_lv_peer(state, lv)
    viewers = Enum.count(state.peers, fn {_pc, peer} -> peer.role == :viewer end)

    if viewers >= state.config[:max_viewers],
      do: {:reply, {:error, :full}, state},
      else: connect_viewer(state, lv, offer)
  end

  @impl true
  def handle_cast({:ice_candidate, lv, candidate}, state) do
    with {:ok, pc} <- Map.fetch(state.lv_peers, lv),
         {:ok, candidate} <- parse_candidate(candidate) do
      PeerConnection.add_ice_candidate(pc, candidate)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, event}, state) do
    case Map.fetch(state.peers, pc) do
      {:ok, peer} -> {:noreply, handle_peer_event(event, pc, peer, state)}
      # Late events from a connection that was already dropped
      :error -> {:noreply, state}
    end
  end

  # A LiveView went away (tab closed, navigated away), so its connection goes too
  def handle_info({:DOWN, _ref, :process, lv, _reason}, state) do
    {:noreply, drop_lv_peer(state, lv)}
  end

  # A PeerConnection crashed, which only affects the browser using it
  def handle_info({:EXIT, pc, reason}, state) when is_map_key(state.peers, pc) do
    Logger.warning("Screen peer connection exited", reason: inspect(reason))
    {:noreply, remove_peer(state, pc, stop_pc: false)}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  # Cancelling a timer doesn't remove a message it already sent, so only the latest one counts
  def handle_info({:idle_timeout, timer}, %{idle_timer: timer, publisher: nil} = state) do
    {:stop, :normal, %{state | end_reason: :idle}}
  end

  def handle_info({:idle_timeout, _timer}, state), do: {:noreply, state}

  def handle_info(:max_duration, state) do
    {:stop, :normal, %{state | end_reason: :max_duration}}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(Map.keys(state.peers), &stop_peer_connection/1)

    room = %{state.room | live?: false, viewer_count: 0}
    Screens.broadcast(room, :ended)

    :telemetry.execute(
      [:botchini, :screens, :room, :stop],
      %{duration: System.monotonic_time() - state.started_at, peak_viewers: state.peak_viewers},
      %{reason: state.end_reason}
    )

    Logger.info("Screen room ended", event: "screen_room_ended", reason: state.end_reason)
  end

  ## Peer events

  defp handle_peer_event({:ice_candidate, candidate}, _pc, peer, state) do
    send(peer.lv, {:screens, state.room.id, {:ice_candidate, ICECandidate.to_json(candidate)}})
    state
  end

  defp handle_peer_event({:track, track}, pc, %{role: :publisher}, state) do
    update_in(state, [:peers, pc, :tracks], &Map.put(&1, track.id, track.kind))
  end

  defp handle_peer_event({:rtp, track_id, _rid, packet}, _pc, %{role: :publisher} = peer, state) do
    case Map.fetch(peer.tracks, track_id) do
      {:ok, kind} -> forward_rtp(state, kind, packet)
      :error -> state
    end
  end

  # Browsers ask for a keyframe when they join or can't decode the video anymore,
  # which only the broadcaster can produce
  defp handle_peer_event({:rtcp, packets}, _pc, %{role: :viewer}, state) do
    if Enum.any?(packets, &match?({_track_id, %PLI{}}, &1)),
      do: request_keyframe(state),
      else: state
  end

  defp handle_peer_event({:connection_state_change, :connected}, pc, peer, state) do
    state = put_in(state, [:peers, pc, :connected?], true)

    case peer.role do
      :publisher ->
        Logger.info("Screen broadcaster connected", event: "screen_broadcaster_connected")
        event = if state.went_live?, do: :updated, else: :live

        %{state | went_live?: true}
        |> cancel_idle_timeout()
        |> update_room(%{live?: true}, event)

      :viewer ->
        :telemetry.execute([:botchini, :screens, :viewer, :join], %{count: 1}, %{})

        state
        |> request_keyframe()
        |> update_viewer_count()
    end
  end

  defp handle_peer_event({:connection_state_change, conn_state}, pc, _peer, state)
       when conn_state in [:failed, :closed] do
    remove_peer(state, pc)
  end

  defp handle_peer_event(_event, _pc, _peer, state), do: state

  # Padding-only packets carry no media, and the VP8 munger can't parse them
  defp forward_rtp(state, _kind, %{payload: <<>>}), do: state

  defp forward_rtp(state, kind, packet) do
    case munge(state.mungers[kind], packet) do
      {:ok, packet, munger} ->
        for {pc, %{role: :viewer, connected?: true} = viewer} <- state.peers do
          PeerConnection.send_rtp(pc, viewer.tracks[kind], packet)
        end

        put_in(state, [:mungers, kind], munger)

      :error ->
        state
    end
  end

  # The VP8 munger pattern matches on well-formed payloads, and a single
  # malformed packet shouldn't end the whole room
  defp munge(munger, packet) do
    {packet, munger} = Munger.munge(munger, packet)
    {:ok, packet, munger}
  rescue
    error in [MatchError, FunctionClauseError] ->
      Logger.debug("Dropped unparseable RTP packet: #{Exception.message(error)}")
      :error
  end

  defp request_keyframe(%{publisher: nil} = state), do: state

  defp request_keyframe(state) do
    now = System.monotonic_time(:millisecond)
    publisher = state.peers[state.publisher]

    video_track =
      Enum.find_value(publisher.tracks, fn {id, kind} -> if kind == :video, do: id end)

    recent? =
      state.last_keyframe_request != nil and
        now - state.last_keyframe_request < @keyframe_interval_ms

    if video_track && not recent? do
      PeerConnection.send_pli(state.publisher, video_track)
      %{state | last_keyframe_request: now}
    else
      state
    end
  end

  ## Peers

  defp connect_viewer(state, lv, offer) do
    # Viewers get their own outbound tracks right away, so they can connect before
    # the broadcaster does and start receiving as soon as the screen is shared
    stream_id = MediaStreamTrack.generate_stream_id()
    tracks = Map.new([:video, :audio], &{&1, MediaStreamTrack.new(&1, [stream_id])})

    case negotiate(state, offer, &add_tracks(&1, Map.values(tracks))) do
      {:ok, pc, answer} ->
        outbound = Map.new(tracks, fn {kind, track} -> {kind, track.id} end)
        {:reply, {:ok, answer}, put_peer(state, pc, new_peer(:viewer, lv, outbound))}

      {:error, reason} ->
        Logger.warning("Failed to connect screen viewer", reason: inspect(reason))
        {:reply, {:error, reason}, state}
    end
  end

  defp negotiate(state, offer, before_answer) do
    with {:ok, offer} <- parse_offer(offer),
         {:ok, pc} <- PeerConnection.start_link(peer_connection_options(state.config)),
         :ok <- negotiate_answer(pc, offer, before_answer) do
      {:ok, pc, SessionDescription.to_json(PeerConnection.get_local_description(pc))}
    end
  end

  defp negotiate_answer(pc, offer, before_answer) do
    with :ok <- PeerConnection.set_remote_description(pc, offer),
         :ok <- before_answer.(pc),
         {:ok, answer} <- PeerConnection.create_answer(pc),
         :ok <- PeerConnection.set_local_description(pc, answer) do
      :ok
    else
      error ->
        stop_peer_connection(pc)
        error
    end
  catch
    # Offers come from anyone with the link, and one that crashes the
    # PeerConnection mustn't take the room down with it
    :exit, reason ->
      stop_peer_connection(pc)
      {:error, {:negotiation_failed, reason}}
  end

  defp add_tracks(pc, tracks) do
    Enum.reduce_while(tracks, :ok, fn track, :ok ->
      case PeerConnection.add_track(pc, track) do
        {:ok, _sender} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp peer_connection_options(config) do
    [
      ice_servers: config[:ice_servers],
      ice_port_range: config[:ice_port_range] || [0],
      host_to_srflx_ip_mapper: srflx_mapper(config[:public_ip]),
      # Forwarded packets are sent as they arrive, so broadcaster and viewers
      # must agree on one codec per kind, and every browser supports these
      audio_codecs: [:opus],
      video_codecs: [:vp8]
    ]
  end

  # Behind NAT, the host candidates are private addresses the browsers can't
  # reach, so the public one (with the ICE ports forwarded) is announced too
  defp srflx_mapper(nil), do: nil
  defp srflx_mapper(public_ip), do: fn _host_ip -> public_ip end

  defp new_peer(role, lv, tracks) do
    # Publisher tracks map inbound track id => kind, viewer tracks map kind => outbound track id
    %{role: role, lv: lv, lv_ref: Process.monitor(lv), connected?: false, tracks: tracks}
  end

  defp put_peer(state, pc, peer) do
    state
    |> put_in([:peers, pc], peer)
    |> put_in([:lv_peers, peer.lv], pc)
  end

  defp drop_lv_peer(state, lv) do
    case Map.fetch(state.lv_peers, lv) do
      {:ok, pc} -> remove_peer(state, pc)
      :error -> state
    end
  end

  defp drop_publisher(%{publisher: nil} = state), do: state
  defp drop_publisher(state), do: remove_peer(state, state.publisher)

  defp remove_peer(state, pc, opts \\ []) do
    {peer, peers} = Map.pop(state.peers, pc)
    Process.demonitor(peer.lv_ref, [:flush])
    if Keyword.get(opts, :stop_pc, true), do: stop_peer_connection(pc)

    state = %{state | peers: peers, lv_peers: Map.delete(state.lv_peers, peer.lv)}

    case peer.role do
      :viewer ->
        update_viewer_count(state)

      :publisher when state.publisher == pc ->
        Logger.info("Screen broadcaster disconnected", event: "screen_broadcaster_disconnected")

        %{state | publisher: nil}
        |> update_room(%{live?: false}, :updated)
        |> schedule_idle_timeout(state.config[:reconnect_timeout_ms])

      :publisher ->
        state
    end
  end

  defp stop_peer_connection(pc) do
    Process.unlink(pc)
    PeerConnection.stop(pc)
  catch
    :exit, _reason -> :ok
  end

  defp parse_offer(%{"type" => "offer", "sdp" => sdp}) when is_binary(sdp),
    do: {:ok, %SessionDescription{type: :offer, sdp: sdp}}

  defp parse_offer(_offer), do: {:error, :invalid_offer}

  defp parse_candidate(%{"candidate" => candidate} = json) when is_binary(candidate) do
    {:ok,
     %ICECandidate{
       candidate: candidate,
       sdp_mid: json["sdpMid"],
       sdp_m_line_index: json["sdpMLineIndex"],
       username_fragment: json["usernameFragment"]
     }}
  end

  defp parse_candidate(_candidate), do: :error

  ## Room state

  defp update_viewer_count(state) do
    count =
      Enum.count(state.peers, fn {_pc, peer} -> peer.role == :viewer and peer.connected? end)

    if count == state.room.viewer_count do
      state
    else
      %{state | peak_viewers: max(state.peak_viewers, count)}
      |> update_room(%{viewer_count: count}, :updated)
    end
  end

  defp update_room(state, changes, event) do
    room = struct!(state.room, changes)
    Screens.broadcast(room, event)
    %{state | room: room}
  end

  defp schedule_idle_timeout(state, timeout) do
    state = cancel_idle_timeout(state)
    timer = make_ref()
    Process.send_after(self(), {:idle_timeout, timer}, timeout)
    %{state | idle_timer: timer}
  end

  defp cancel_idle_timeout(state), do: %{state | idle_timer: nil}
end
