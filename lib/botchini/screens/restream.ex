defmodule Botchini.Screens.Restream do
  @moduledoc """
  A YouTube video, or a YouTube or Twitch live stream, shown on a guild's page as
  one of its screens, at the same moment for everyone. Anyone adds links, pauses
  them, skips through videos and stops them, and a guild shows one at a time.

  The link is looked up first, for its title and to turn down what can't be
  shown. Then a room is made for it, and `Pipeline` sends the video and the
  audio here as RTP, which this process hands to the room like a broadcaster
  would. The room goes live with the first packet, and ends when the video or
  the live stream does. Closing the room stops the video too.

  Pausing stops the pipeline, leaving everyone on the last picture. Playing
  again starts another one where the video was, or where a live stream is now,
  and so does skipping to another moment of a video. They all read the media
  links the lookup found, which are looked up again once if they stopped working.

  Pages get `{:restream, {:state, state}}` messages once they subscribe, with
  `nil` once nothing is shown. Who added the link gets a
  `{:restream, {:failed, reason}}` message when it can't be shown.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Botchini.Music.{PlaybackFailure, YtDlp}
  alias Botchini.Screens
  alias Botchini.Screens.Restream.Pipeline
  alias Botchini.Screens.Room

  @max_url_length 500
  @max_title_length 100
  # yt-dlp and ffmpeg take a few seconds to start, live streams up to 15
  @start_timeout_ms :timer.minutes(1)
  # The end of what yt-dlp and ffmpeg printed, to tell why they failed
  @max_output_bytes 4_000

  @type status :: :looking_up | :starting | :live | :paused

  @typedoc """
  What the pages show. The title is the link until it's looked up. Videos have a
  duration, and the position is where they were when this was sent, which goes
  on while it's `:live`
  """
  @type state :: %{
          status: status(),
          title: String.t(),
          url: String.t(),
          added_by: String.t(),
          paused_by: String.t() | nil,
          room_id: String.t() | nil,
          duration_ms: pos_integer() | nil,
          position_ms: non_neg_integer()
        }

  @type start_error :: :blank | :unsupported_url | :already_showing

  @type user :: %{id: String.t(), name: String.t()}

  @spec start_link({String.t(), String.t(), user(), pid()}) :: GenServer.on_start()
  def start_link({guild_id, _url, _user, _requester} = args),
    do: GenServer.start_link(__MODULE__, args, name: via(guild_id))

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(guild_id), do: Phoenix.PubSub.subscribe(Botchini.PubSub, topic(guild_id))

  @spec max_url_length() :: pos_integer()
  def max_url_length, do: @max_url_length

  @doc """
  Starts showing the link on the guild's page. It's looked up meanwhile, and the
  calling process is told when it can't be shown
  """
  @spec start(String.t(), String.t(), user()) :: :ok | {:error, start_error()}
  def start(guild_id, url, user) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" ->
        {:error, :blank}

      String.length(url) > @max_url_length or not YtDlp.stream_url?(url) ->
        {:error, :unsupported_url}

      true ->
        case DynamicSupervisor.start_child(
               Screens.RestreamSupervisor,
               {__MODULE__, {guild_id, url, user, self()}}
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> {:error, :already_showing}
        end
    end
  end

  @doc """
  What the guild's page is showing, if anything
  """
  @spec state(String.t()) :: state() | nil
  def state(guild_id) do
    GenServer.call(via(guild_id), :state)
  catch
    :exit, _not_running -> nil
  end

  @doc """
  Pauses the video or live stream for everyone, once it's showing
  """
  @spec pause(String.t(), user()) :: :ok
  def pause(guild_id, user), do: call(guild_id, {:pause, user})

  @doc """
  Plays it again where it was paused. Live streams carry on from where they are now
  """
  @spec resume(String.t()) :: :ok
  def resume(guild_id), do: call(guild_id, :resume)

  @doc """
  Skips to another moment of a video, which stays paused if it is
  """
  @spec seek(String.t(), integer()) :: :ok
  def seek(guild_id, position_ms) when is_integer(position_ms),
    do: call(guild_id, {:seek, position_ms})

  defp call(guild_id, message) do
    GenServer.call(via(guild_id), message)
  catch
    :exit, _not_running -> :ok
  end

  @doc """
  Stops showing the video, ending its room, which says who stopped it
  """
  @spec stop(String.t(), user()) :: :ok
  def stop(guild_id, user), do: call(guild_id, {:stop, user})

  defp via(guild_id), do: {:via, Registry, {Screens.RestreamRegistry, guild_id}}
  defp topic(guild_id), do: "screens:restream:#{guild_id}"

  ## Callbacks

  @impl true
  def init({guild_id, url, user, requester}) do
    Process.flag(:trap_exit, true)
    Logger.metadata(guild_id: guild_id, restream_url: url)

    state =
      %{
        guild_id: guild_id,
        url: url,
        title: url,
        user: user,
        requester: requester,
        status: :looking_up,
        lookup: lookup(url),
        # Whether the room went live, which it stays while paused
        live?: false,
        duration_ms: nil,
        media: [],
        # Whether the links were looked up since a pipeline last played them, so
        # a pipeline failing with them isn't from them expiring
        refreshed?: true,
        # Where the running pipeline started, or where the next one will
        offset_ms: 0,
        # When the running pipeline's first packet came, as monotonic milliseconds
        playing_since: nil,
        paused_by: nil,
        room_id: nil,
        room_ref: nil,
        sockets: %{},
        port: nil,
        output: "",
        start_timer: nil,
        end_reason: :stopped,
        end_detail: nil
      }
      |> broadcast()

    Logger.info("Restream started", event: "restream_started")
    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, public(state), state}

  def handle_call({:stop, user}, _from, state),
    do:
      {:stop, :normal, :ok,
       %{state | end_reason: :video_stopped, end_detail: "stopped by #{user.name}"}}

  # Not before it went live, as there's nothing to pause yet. Links being looked
  # up again aren't played once they're found
  def handle_call({:pause, user}, _from, %{live?: true, port: port, lookup: lookup} = state)
      when port != nil or lookup != nil do
    Logger.info("Restream paused", event: "restream_paused")

    state =
      %{
        close_pipeline(state)
        | offset_ms: position_ms(state),
          status: :paused,
          paused_by: user.name
      }

    {:reply, :ok, broadcast(state)}
  end

  def handle_call(:resume, _from, %{status: :paused} = state) do
    Logger.info("Restream resumed", event: "restream_resumed")
    {:reply, :ok, start_pipeline(%{state | paused_by: nil})}
  end

  # Live streams can't be skipped through. The video stays a second from its
  # end, which still shows how it ends
  def handle_call({:seek, position_ms}, _from, %{live?: true, duration_ms: duration} = state)
      when duration != nil do
    offset_ms = position_ms |> max(0) |> min(duration - 1_000) |> max(0)

    # Links being looked up again start there once they're found
    state =
      if state.status == :paused or state.lookup != nil,
        do: broadcast(%{state | offset_ms: offset_ms}),
        else: start_pipeline(%{close_pipeline(state) | offset_ms: offset_ms})

    {:reply, :ok, state}
  end

  def handle_call(_pause_resume_or_seek, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({ref, result}, %{lookup: %Task{ref: ref}, room_id: nil} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | lookup: nil}

    with {:ok, stream} <- result,
         {:ok, state} <- start_room(state, stream) do
      {:noreply, start_pipeline(state)}
    else
      {:error, reason} -> fail(state, reason)
    end
  end

  # The links looked up again, unless it was paused meanwhile
  def handle_info({ref, result}, %{lookup: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | lookup: nil}

    case result do
      {:ok, %{media: media}} when state.status == :paused ->
        {:noreply, %{state | media: media}}

      {:ok, %{media: media}} ->
        {:noreply, start_pipeline(%{state | media: media})}

      {:error, reason} ->
        Logger.warning("Restream couldn't find its media again", reason: inspect(reason))
        {:stop, :normal, %{state | end_reason: :link_failed}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{lookup: %Task{ref: ref}} = state) do
    Logger.error("Restream lookup crashed", reason: inspect(reason))
    state = %{state | lookup: nil}

    if state.live?,
      do: {:stop, :normal, %{state | end_reason: :link_failed}},
      else: fail(state, :unknown)
  end

  # The room ended on its own, like after streaming for too long
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{room_ref: ref} = state),
    do: {:stop, :normal, %{state | room_id: nil}}

  # Only RTP is forwarded, ffmpeg's RTCP reports are for its receivers
  def handle_info({:udp, _socket, _ip, _port, <<_::8, type, _::binary>>}, state)
      when type in 192..223,
      do: {:noreply, state}

  def handle_info({:udp, socket, _ip, _port, data}, state) do
    with {:ok, kind} <- socket_kind(state, socket),
         {:ok, packet} <- ExRTP.Packet.decode(data) do
      state = go_live(state)
      Room.send_rtp(state.room_id, kind, packet)
      {:noreply, state}
    else
      _unknown_socket_or_not_rtp -> {:noreply, state}
    end
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) do
    output = state.output <> data
    skip = max(byte_size(output) - @max_output_bytes, 0)
    {:noreply, %{state | output: binary_part(output, skip, byte_size(output) - skip)}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    state = %{state | port: nil}

    cond do
      not state.live? ->
        Logger.warning("Restream couldn't start", exit_status: status, output: state.output)
        fail(state, state.output |> PlaybackFailure.classify() |> elem(0))

      # The links may have expired since they last played
      state.playing_since == nil and not state.refreshed? ->
        Logger.info("Restream looking up its media again",
          exit_status: status,
          output: state.output
        )

        {:noreply, %{close_pipeline(state) | lookup: lookup(state.url), refreshed?: true}}

      state.playing_since == nil ->
        Logger.warning("Restream couldn't start again", exit_status: status, output: state.output)
        {:stop, :normal, %{state | end_reason: :link_failed}}

      status == 0 ->
        Logger.info("Restream finished", event: "restream_finished")
        {:stop, :normal, %{state | end_reason: :finished}}

      true ->
        Logger.warning("Restream broke", exit_status: status, output: state.output)
        {:stop, :normal, %{state | end_reason: :link_failed}}
    end
  end

  # Pipelines closed after a pause or a skip can still have said something
  def handle_info({port, _data_or_exit_status}, state) when is_port(port),
    do: {:noreply, state}

  def handle_info({:start_timeout, timer}, %{start_timer: timer} = state) do
    Logger.warning("Restream took too long to start", output: state.output)

    if state.live?,
      do: {:stop, :normal, %{state | end_reason: :link_failed}},
      else: fail(state, :timeout)
  end

  def handle_info({:start_timeout, _timer}, state), do: {:noreply, state}

  # The lookup, the room once it's broadcasting and the port are linked, and
  # their ends are handled above
  def handle_info({:EXIT, _pid_or_port, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    close_pipeline(state)
    if state.room_id, do: Room.stop(state.room_id, state.end_reason, state.end_detail)
    broadcast(state.guild_id, nil)
    Logger.info("Restream ended", event: "restream_ended", reason: state.end_reason)
  end

  ## Steps

  defp lookup(url), do: Task.async(fn -> YtDlp.lookup_stream(url, Pipeline.format()) end)

  defp start_room(state, stream) do
    attrs = %{
      title: String.slice(stream.title, 0, @max_title_length),
      guild_id: state.guild_id,
      # The page is the only place it's shown, so it isn't posted on Discord
      channel_id: nil,
      owner_id: state.user.id,
      owner_name: state.user.name
    }

    with {:ok, room} <- Screens.start_link_room(attrs),
         pid when is_pid(pid) <- Room.whereis(room.id) || {:error, :unknown} do
      Logger.metadata(screen_room_id: room.id)

      {:ok,
       %{
         state
         | title: room.title,
           url: stream.url,
           duration_ms: stream.duration_ms,
           media: stream.media,
           room_id: room.id,
           room_ref: Process.monitor(pid)
       }}
    end
  end

  defp start_pipeline(state) do
    {:ok, video} = :gen_udp.open(0, udp_options())
    {:ok, audio} = :gen_udp.open(0, udp_options())
    {:ok, video_port} = :inet.port(video)
    {:ok, audio_port} = :inet.port(audio)

    timer = make_ref()
    Process.send_after(self(), {:start_timeout, timer}, @start_timeout_ms)

    # Live streams start where they are now
    start_s = if state.duration_ms, do: div(state.offset_ms, 1_000), else: 0

    %{
      state
      | status: :starting,
        offset_ms: start_s * 1_000,
        playing_since: nil,
        sockets: %{video => :video, audio => :audio},
        port: Pipeline.open(state.media, video_port, audio_port, start_s),
        output: "",
        start_timer: timer
    }
    |> broadcast()
  end

  # The sockets go too, so packets the old ffmpeg still sends are dropped
  defp close_pipeline(state) do
    if state.port, do: Pipeline.close(state.port)
    Enum.each(Map.keys(state.sockets), &:gen_udp.close/1)
    %{state | port: nil, sockets: %{}, playing_since: nil, start_timer: nil}
  end

  # Only ffmpeg on this machine sends here. A big buffer holds the video's
  # keyframes, which come as bursts of packets
  defp udp_options,
    do: [:binary, ip: {127, 0, 0, 1}, active: true, recbuf: 1_048_576]

  defp socket_kind(state, socket), do: Map.fetch(state.sockets, socket)

  defp go_live(%{playing_since: since} = state) when since != nil, do: state

  # The first packet of each pipeline. A room that just ended is noticed by its monitor
  defp go_live(state) do
    case Room.publish_rtp(state.room_id) do
      :ok ->
        if not state.live?, do: Logger.info("Restream went live", event: "restream_live")

        broadcast(%{
          state
          | live?: true,
            refreshed?: false,
            status: :live,
            playing_since: System.monotonic_time(:millisecond),
            start_timer: nil
        })

      {:error, :not_found} ->
        state
    end
  end

  defp position_ms(%{playing_since: nil} = state), do: state.offset_ms

  defp position_ms(state) do
    position = state.offset_ms + System.monotonic_time(:millisecond) - state.playing_since
    if state.duration_ms, do: min(position, state.duration_ms), else: position
  end

  # Nothing was shown, so the room goes without a word in the activity
  defp fail(state, reason) do
    send(state.requester, {:restream, {:failed, reason}})
    {:stop, :normal, state}
  end

  defp public(state) do
    %{
      status: state.status,
      title: state.title,
      url: state.url,
      added_by: state.user.name,
      paused_by: state.paused_by,
      room_id: state.room_id,
      duration_ms: state.duration_ms,
      position_ms: position_ms(state)
    }
  end

  defp broadcast(state) do
    broadcast(state.guild_id, public(state))
    state
  end

  defp broadcast(guild_id, public) do
    Phoenix.PubSub.broadcast(Botchini.PubSub, topic(guild_id), {:restream, {:state, public}})
  end
end
