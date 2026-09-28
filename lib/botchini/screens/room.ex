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
          viewer_count: non_neg_integer(),
          source: source() | nil,
          custom_title?: boolean()
        }

  @type source :: :screen | :window | :tab | :obs

  @enforce_keys [:id, :broadcast_key, :title, :guild_id, :channel_id, :owner_id, :owner_name]
  defstruct @enforce_keys ++
              [:started_at, :source, live?: false, viewer_count: 0, custom_title?: false]

  @max_title_length 100
  @whip_gathering_timeout_ms 2_000

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

  @spec publish_whip(String.t(), String.t()) :: {:ok, String.t(), String.t()} | {:error, term()}
  def publish_whip(room_id, sdp) when is_binary(sdp), do: call(room_id, {:publish_whip, sdp})

  @spec end_whip(String.t(), String.t()) :: :ok | {:error, :not_found}
  def end_whip(room_id, session_id), do: call(room_id, {:end_whip, session_id})

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

  @spec set_title(String.t(), String.t()) :: :ok | {:error, :not_found}
  def set_title(room_id, title) when is_binary(title), do: call(room_id, {:set_title, title})

  @spec set_source(String.t(), source()) :: :ok | {:error, :not_found}
  def set_source(room_id, source) when source in [:screen, :window, :tab],
    do: call(room_id, {:set_source, source})

  @spec default_title(String.t(), source() | nil) :: String.t()
  def default_title(owner_name, :tab), do: "#{owner_name}'s tab"
  def default_title(owner_name, :window), do: "#{owner_name}'s window"
  def default_title(owner_name, :obs), do: "#{owner_name}'s stream"
  def default_title(owner_name, _source), do: "#{owner_name}'s screen"

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
    # Every log of the room says which stream it's about, for the Grafana dashboard
    Logger.metadata(
      screen_room_id: room.id,
      guild_id: room.guild_id,
      screen_title: room.title,
      screen_owner_id: room.owner_id,
      screen_owner_name: room.owner_name
    )

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
        mungers: %{video: Munger.new(:h264, 90_000), audio: Munger.new(:opus, 48_000)},
        # Viewers connecting before the broadcaster get the codec most broadcasters
        # send, and reconnect if theirs turns out to be another
        video_codec: :h264,
        whip_answers: %{},
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

  def handle_call({:set_title, title}, _from, state) do
    changes =
      case title |> String.trim() |> String.slice(0, @max_title_length) do
        "" ->
          %{title: default_title(state.room.owner_name, state.room.source), custom_title?: false}

        title ->
          %{title: title, custom_title?: true}
      end

    {:reply, :ok, rename(state, changes)}
  end

  def handle_call({:set_source, source}, _from, state) do
    {:reply, :ok, rename(state, source_changes(state.room, source))}
  end

  def handle_call({:stop, reason}, _from, state) do
    {:stop, :normal, :ok, %{state | end_reason: reason}}
  end

  def handle_call({:publish, lv, offer}, _from, state) do
    state =
      state
      |> drop_lv_peer(lv)
      |> drop_publisher()

    case negotiate_publisher(state, offer) do
      {:ok, pc, answer, video_codec} ->
        state =
          state
          |> put_peer(pc, new_peer(:publisher, lv, %{}))
          |> Map.put(:publisher, pc)
          |> use_codec(video_codec)

        {:reply, {:ok, answer}, state}

      {:error, reason} ->
        Logger.warning("Failed to connect screen broadcaster", reason: inspect(reason))
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:publish_whip, sdp}, from, state) do
    state = drop_publisher(state)

    case negotiate(state, %{"type" => "offer", "sdp" => sdp}, :h264, fn _pc -> :ok end) do
      {:ok, pc, _answer} ->
        peer = Map.put(new_peer(:publisher, nil, %{}), :session_id, random_id())
        Process.send_after(self(), {:whip_answer_timeout, pc}, @whip_gathering_timeout_ms)

        state =
          state
          |> put_peer(pc, peer)
          |> Map.put(:publisher, pc)
          |> use_codec(:h264)
          |> rename(source_changes(state.room, :obs))
          |> put_in([:whip_answers, pc], from)

        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Failed to connect OBS broadcaster", reason: inspect(reason))
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:end_whip, session_id}, _from, state) do
    case state.publisher && state.peers[state.publisher] do
      %{session_id: ^session_id} -> {:stop, :normal, :ok, %{state | end_reason: :stopped}}
      _peer -> {:reply, {:error, :not_found}, state}
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

  def handle_info({:whip_answer_timeout, pc}, state), do: {:noreply, answer_whip(state, pc)}

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

  defp handle_peer_event({:ice_candidate, _candidate}, _pc, %{lv: nil}, state), do: state

  defp handle_peer_event({:ice_candidate, candidate}, _pc, peer, state) do
    send(peer.lv, {:screens, state.room.id, {:ice_candidate, ICECandidate.to_json(candidate)}})
    state
  end

  defp handle_peer_event({:ice_gathering_state_change, :complete}, pc, _peer, state),
    do: answer_whip(state, pc)

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
        event = if state.went_live?, do: :updated, else: :live
        log_broadcaster_connected(event)

        %{state | went_live?: true}
        |> cancel_idle_timeout()
        |> update_room(%{live?: true}, event)

      :viewer ->
        :telemetry.execute([:botchini, :screens, :viewer, :join], %{count: 1}, %{})
        state = state |> request_keyframe() |> update_viewer_count()

        Logger.info("Screen viewer started watching",
          event: "screen_viewer_joined",
          viewer_count: state.room.viewer_count
        )

        state
    end
  end

  defp handle_peer_event({:connection_state_change, conn_state}, pc, _peer, state)
       when conn_state in [:failed, :closed] do
    remove_peer(state, pc)
  end

  defp handle_peer_event(_event, _pc, _peer, state), do: state

  defp log_broadcaster_connected(:live) do
    :telemetry.execute([:botchini, :screens, :room, :live], %{count: 1}, %{})
    Logger.info("Screen share went live", event: "screen_share_live")
  end

  defp log_broadcaster_connected(:updated) do
    Logger.info("Screen broadcaster reconnected", event: "screen_broadcaster_reconnected")
  end

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

    case negotiate(state, offer, state.video_codec, &add_tracks(&1, Map.values(tracks))) do
      {:ok, pc, answer} ->
        outbound = Map.new(tracks, fn {kind, track} -> {kind, track.id} end)
        {:reply, {:ok, answer}, put_peer(state, pc, new_peer(:viewer, lv, outbound))}

      {:error, reason} ->
        Logger.warning("Failed to connect screen viewer", reason: inspect(reason))
        {:reply, {:error, reason}, state}
    end
  end

  # Browsers mostly encode H.264 on the GPU, which keeps high resolutions at 60 fps
  # smooth, and the ones that can't send it get VP8 instead
  defp negotiate_publisher(state, offer) do
    case negotiate_publisher(state, offer, :h264) do
      {:error, :video_rejected} -> negotiate_publisher(state, offer, :vp8)
      result -> result
    end
  end

  defp negotiate_publisher(state, offer, video_codec) do
    with {:ok, pc, answer} <- negotiate(state, offer, video_codec, fn _pc -> :ok end) do
      if video_rejected?(pc) do
        stop_peer_connection(pc)
        {:error, :video_rejected}
      else
        {:ok, pc, answer, video_codec}
      end
    end
  end

  # An offer without the codec gets its video rejected, instead of an error
  defp video_rejected?(pc) do
    PeerConnection.get_local_description(pc).sdp
    |> ExSDP.parse!()
    |> Map.fetch!(:media)
    |> Enum.any?(&(&1.type == :video and &1.port == 0))
  end

  defp negotiate(state, offer, video_codec, before_answer) do
    options = peer_connection_options(state.config, video_codec)

    with {:ok, offer} <- parse_offer(offer),
         {:ok, pc} <- PeerConnection.start_link(options),
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

  defp peer_connection_options(config, video_codec) do
    [
      ice_servers: config[:ice_servers],
      ice_port_range: config[:ice_port_range] || [0],
      host_to_srflx_ip_mapper: srflx_mapper(config[:announced_ip]),
      # Forwarded packets are sent as they arrive, so broadcaster and viewers
      # must agree on one codec per kind, and every browser supports these
      audio_codecs: [:opus],
      video_codecs: [video_codec]
    ]
  end

  # In a container the host candidates are internal addresses the browsers can't
  # reach, so another one (like the server's LAN IP) is announced alongside the
  # public address STUN finds, with the ICE ports published on it
  defp srflx_mapper(nil), do: nil
  defp srflx_mapper(announced_ip), do: fn _host_ip -> announced_ip end

  defp new_peer(role, lv, tracks) do
    # Publisher tracks map inbound track id => kind, viewer tracks map kind => outbound track id
    %{role: role, lv: lv, lv_ref: lv && Process.monitor(lv), connected?: false, tracks: tracks}
  end

  defp put_peer(state, pc, peer) do
    state
    |> put_in([:peers, pc], peer)
    |> then(&if(peer.lv, do: put_in(&1, [:lv_peers, peer.lv], pc), else: &1))
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
    if peer.lv_ref, do: Process.demonitor(peer.lv_ref, [:flush])
    if Keyword.get(opts, :stop_pc, true), do: stop_peer_connection(pc)

    {waiting, whip_answers} = Map.pop(state.whip_answers, pc)
    if waiting, do: GenServer.reply(waiting, {:error, :closed})

    state = %{
      state
      | peers: peers,
        lv_peers: Map.delete(state.lv_peers, peer.lv),
        whip_answers: whip_answers
    }

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

  defp answer_whip(state, pc) do
    case Map.pop(state.whip_answers, pc) do
      {nil, _answers} ->
        state

      {from, answers} ->
        sdp = PeerConnection.get_local_description(pc).sdp
        GenServer.reply(from, {:ok, sdp, state.peers[pc].session_id})
        %{state | whip_answers: answers}
    end
  end

  defp use_codec(%{video_codec: codec} = state, codec) do
    update_in(state, [:mungers], &Map.new(&1, fn {kind, m} -> {kind, Munger.update(m)} end))
  end

  defp use_codec(state, codec) do
    for {_pc, %{role: :viewer, lv: lv}} <- state.peers,
        do: send(lv, {:screens, state.room.id, :reconnect})

    %{
      state
      | video_codec: codec,
        mungers: %{video: Munger.new(codec, 90_000), audio: Munger.update(state.mungers.audio)}
    }
  end

  defp source_changes(%{custom_title?: true}, source), do: %{source: source}

  defp source_changes(room, source),
    do: %{source: source, title: default_title(room.owner_name, source)}

  defp random_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

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

  defp rename(state, changes) do
    if Map.take(state.room, Map.keys(changes)) == changes do
      state
    else
      Logger.metadata(screen_title: changes[:title] || state.room.title)
      update_room(state, changes, :updated)
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
