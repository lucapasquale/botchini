defmodule Botchini.Screens.Restream do
  @moduledoc """
  A YouTube video, or a YouTube or Twitch live stream, shown on a guild's page as
  one of its screens, at the same moment for everyone. Only admins add links,
  and a guild shows one at a time.

  The link is looked up first, for its title and to turn down what can't be
  shown. Then a room is made for it, and `Pipeline` sends the video and the
  audio here as RTP, which this process hands to the room like a broadcaster
  would. The room goes live with the first packet, and ends when the video or
  the live stream does. Closing the room stops the video too.

  Pages get `{:restream, {:state, state}}` messages once they subscribe, with
  `nil` once nothing is shown. The admin who added the link gets a
  `{:restream, {:failed, reason}}` message when it can't be shown.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Botchini.Music.YtDlp
  alias Botchini.Screens
  alias Botchini.Screens.Restream.Pipeline
  alias Botchini.Screens.Room

  @max_url_length 500
  @max_title_length 100
  # yt-dlp and ffmpeg take a few seconds to start, live streams up to 15
  @start_timeout_ms :timer.minutes(1)
  # The end of what yt-dlp and ffmpeg printed, to tell why they failed
  @max_output_bytes 4_000

  @type status :: :looking_up | :starting | :live

  @typedoc """
  What the admins' menu shows. The title is the link until it's looked up
  """
  @type state :: %{
          status: status(),
          title: String.t(),
          url: String.t(),
          added_by: String.t(),
          room_id: String.t() | nil
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
  Stops showing the video, ending its room. Only admins can, which the pages check
  """
  @spec stop(String.t()) :: :ok
  def stop(guild_id) do
    GenServer.call(via(guild_id), :stop)
  catch
    :exit, _not_running -> :ok
  end

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
        lookup: Task.async(fn -> YtDlp.lookup_stream(url) end),
        live?: false,
        room_id: nil,
        room_ref: nil,
        sockets: %{},
        port: nil,
        output: "",
        start_timer: nil,
        end_reason: :stopped
      }
      |> broadcast()

    Logger.info("Restream started", event: "restream_started")
    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, public(state), state}

  def handle_call(:stop, _from, state),
    do: {:stop, :normal, :ok, %{state | end_reason: :closed_by_admin}}

  @impl true
  def handle_info({ref, result}, %{lookup: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | lookup: nil}

    with {:ok, stream} <- result,
         {:ok, state} <- start_room(state, stream) do
      {:noreply, start_pipeline(state)}
    else
      {:error, reason} -> fail(state, reason)
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{lookup: %Task{ref: ref}} = state) do
    Logger.error("Restream lookup crashed", reason: inspect(reason))
    fail(%{state | lookup: nil}, :unknown)
  end

  # The room ended, closed by an admin or after streaming for too long
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
        fail(state, state.output |> Botchini.Music.PlaybackFailure.classify() |> elem(0))

      status == 0 ->
        Logger.info("Restream finished", event: "restream_finished")
        {:stop, :normal, %{state | end_reason: :finished}}

      true ->
        Logger.warning("Restream broke", exit_status: status, output: state.output)
        {:stop, :normal, %{state | end_reason: :link_failed}}
    end
  end

  def handle_info({:start_timeout, timer}, %{start_timer: timer, live?: false} = state) do
    Logger.warning("Restream took too long to start", output: state.output)
    fail(state, :timeout)
  end

  def handle_info({:start_timeout, _timer}, state), do: {:noreply, state}

  # The lookup, the room once it's broadcasting and the port are linked, and
  # their ends are handled above
  def handle_info({:EXIT, _pid_or_port, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.port, do: Pipeline.close(state.port)
    if state.room_id, do: Room.stop(state.room_id, state.end_reason)
    broadcast(state.guild_id, nil)
    Logger.info("Restream ended", event: "restream_ended", reason: state.end_reason)
  end

  ## Steps

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

    %{
      state
      | status: :starting,
        sockets: %{video => :video, audio => :audio},
        port: Pipeline.open(state.url, video_port, audio_port),
        start_timer: timer
    }
    |> broadcast()
  end

  # Only ffmpeg on this machine sends here. A big buffer holds the video's
  # keyframes, which come as bursts of packets
  defp udp_options,
    do: [:binary, ip: {127, 0, 0, 1}, active: true, recbuf: 1_048_576]

  defp socket_kind(state, socket), do: Map.fetch(state.sockets, socket)

  defp go_live(%{live?: true} = state), do: state

  # A room that just ended is noticed by its monitor
  defp go_live(state) do
    case Room.publish_rtp(state.room_id) do
      :ok ->
        Logger.info("Restream went live", event: "restream_live")
        broadcast(%{state | live?: true, status: :live, start_timer: nil})

      {:error, :not_found} ->
        state
    end
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
      room_id: state.room_id
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
