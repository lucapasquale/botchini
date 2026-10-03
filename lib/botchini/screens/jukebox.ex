defmodule Botchini.Screens.Jukebox do
  @moduledoc """
  Music playing on a guild's screen sharing pages, the same song at the same spot
  for everyone on them. Anyone can add songs from YouTube to the end of the queue,
  and play, pause or skip them, while only admins remove songs from the queue.

  yt-dlp looks songs up as they're added, and downloads the audio of the song
  playing and of the next one, which the pages play from here. This process keeps
  the time: it tells the pages where the song is whenever something changes, and
  moves on to the next song when one ends. Only the songs around the one playing
  are kept on disk, and the queue only lives in memory, so a restart empties it.

  Pages get `{:music, {:state, state}}` messages once they subscribe.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Botchini.Music.YtDlp
  alias Botchini.Screens.Activity

  @max_queue 50
  @max_history 20
  @max_term_length 200
  @max_duration_ms :timer.hours(1)
  # Going back further into a song than this starts it over, like music players do
  @restart_after_ms 5_000
  # Durations are rounded to the second, so songs get a moment more to finish
  @end_grace_ms 1_000
  # YouTube sometimes refuses a download that works right after
  @retried_downloads [:forbidden, :transient, :unknown]

  @type status :: :looking_up | :queued | :downloading | :ready

  @typedoc """
  A song, which only has its search or link as title while it's looked up
  """
  @type track :: %{
          id: String.t(),
          title: String.t(),
          url: String.t() | nil,
          thumbnail: String.t() | nil,
          duration_ms: pos_integer() | nil,
          added_by: String.t(),
          status: status()
        }

  @typedoc """
  What the pages show. `position_ms` is where the current song was when this was
  sent, and keeps going while `playing?`. A song isn't playing while it's paused
  or still downloading
  """
  @type state :: %{
          current: track() | nil,
          queue: [track()],
          paused?: boolean(),
          playing?: boolean(),
          position_ms: non_neg_integer(),
          previous?: boolean()
        }

  @type add_error :: :blank | :full

  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(guild_id), do: GenServer.start_link(__MODULE__, guild_id, name: via(guild_id))

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(guild_id), do: Phoenix.PubSub.subscribe(Botchini.PubSub, topic(guild_id))

  @spec max_term_length() :: pos_integer()
  def max_term_length, do: @max_term_length

  @doc """
  What's playing on the guild's pages and what's next
  """
  @spec state(String.t()) :: state()
  def state(guild_id), do: call(guild_id, :state, public(new_state(guild_id, nil)))

  @doc """
  Adds a YouTube link, or the first video a search finds, to the end of the
  queue. It's looked up meanwhile, and the calling process gets a
  `{:music, {:add_failed, term, reason}}` message when nothing could be found
  """
  @spec add(String.t(), String.t(), %{id: String.t(), name: String.t()}) ::
          :ok | {:error, add_error()}
  def add(guild_id, term, %{name: name}) when is_binary(term) do
    case clean_term(term) do
      "" -> {:error, :blank}
      term -> guild_id |> ensure_started() |> GenServer.call({:add, term, name, self()})
    end
  end

  @doc """
  Pauses the song playing, or plays it again
  """
  @spec toggle(String.t()) :: :ok
  def toggle(guild_id), do: call(guild_id, :toggle, :ok)

  @doc """
  Skips to the next song, telling everyone who skipped it
  """
  @spec next(String.t(), String.t()) :: :ok
  def next(guild_id, actor), do: call(guild_id, {:next, actor}, :ok)

  @doc """
  Goes back to the song played before, or to the start of this one when it's
  been playing for a few seconds
  """
  @spec previous(String.t()) :: :ok
  def previous(guild_id), do: call(guild_id, :previous, :ok)

  @doc """
  Takes a song out of the queue. Only admins can, which the pages check
  """
  @spec remove(String.t(), String.t()) :: :ok
  def remove(guild_id, track_id), do: call(guild_id, {:remove, track_id}, :ok)

  @doc """
  The audio of one of the guild's songs, once it's downloaded
  """
  @spec file(String.t(), String.t()) :: {:ok, Path.t()} | :error
  def file(guild_id, track_id), do: call(guild_id, {:file, track_id}, :error)

  @doc false
  @spec stop(String.t()) :: :ok
  def stop(guild_id) do
    case GenServer.whereis(via(guild_id)) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  # Guilds only get a process once a song is added, before that there's
  # nothing to play or control
  defp call(guild_id, message, fallback) do
    case GenServer.whereis(via(guild_id)) do
      nil -> fallback
      pid -> GenServer.call(pid, message)
    end
  catch
    :exit, {:noproc, _call} -> fallback
  end

  defp ensure_started(guild_id) do
    case DynamicSupervisor.start_child(Botchini.Screens.JukeboxSupervisor, {__MODULE__, guild_id}) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  defp via(guild_id), do: {:via, Registry, {Botchini.Screens.JukeboxRegistry, guild_id}}

  defp topic(guild_id), do: "screens:music:#{guild_id}"

  defp clean_term(term) do
    term
    |> String.replace(~r/[[:cntrl:]]+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_term_length)
  end

  defp dir(guild_id) do
    Application.get_env(:botchini, __MODULE__, [])
    |> Keyword.get_lazy(:dir, fn -> Path.join(System.tmp_dir!(), "botchini-music") end)
    |> Path.join(guild_id)
  end

  ## Callbacks

  @impl true
  def init(guild_id) do
    # So the downloaded songs are removed when the app stops
    Process.flag(:trap_exit, true)

    dir = dir(guild_id)
    File.rm_rf(dir)
    File.mkdir_p!(dir)

    {:ok, new_state(guild_id, dir)}
  end

  @impl true
  def terminate(_reason, state), do: File.rm_rf(state.dir)

  # `started_at` is when the current song's clock started running, from
  # `offset_ms` into it, and is nil while it's stopped
  defp new_state(guild_id, dir) do
    %{
      guild_id: guild_id,
      dir: dir,
      history: [],
      current: nil,
      queue: [],
      paused?: false,
      offset_ms: 0,
      started_at: nil,
      timer: nil,
      tasks: %{}
    }
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, public(state), state}

  def handle_call({:file, track_id}, _from, state) do
    case Enum.find(tracks(state), &(&1.id == track_id and &1.status == :ready)) do
      nil -> {:reply, :error, state}
      track -> {:reply, {:ok, track.file}, state}
    end
  end

  def handle_call({:add, _term, _name, _pid}, _from, state)
      when length(state.queue) >= @max_queue,
      do: {:reply, {:error, :full}, state}

  def handle_call({:add, term, name, pid}, _from, state) do
    track = %{
      id: random_id(),
      title: term,
      url: nil,
      thumbnail: nil,
      duration_ms: nil,
      added_by: name,
      status: :looking_up,
      file: nil
    }

    state =
      %{state | queue: state.queue ++ [track]}
      |> run_task({:lookup, track.id, pid}, fn -> YtDlp.lookup(term) end)

    {:reply, :ok, settle(state)}
  end

  def handle_call(:toggle, _from, %{current: nil} = state), do: {:reply, :ok, state}

  def handle_call(:toggle, _from, state),
    do: {:reply, :ok, settle(%{state | paused?: !state.paused?})}

  def handle_call({:next, _actor}, _from, %{current: nil} = state), do: {:reply, :ok, state}

  def handle_call({:next, actor}, _from, state) do
    Activity.record(state.guild_id, :song_skipped, actor, state.current.title)
    {:reply, :ok, state |> advance() |> settle()}
  end

  def handle_call(:previous, _from, state) do
    state =
      cond do
        state.current && (state.history == [] or position(state) > @restart_after_ms) ->
          put_current(state, state.current)

        state.history != [] ->
          [previous | history] = state.history
          queue = if state.current, do: [state.current | state.queue], else: state.queue
          put_current(%{state | history: history, queue: queue}, previous)

        true ->
          state
      end

    {:reply, :ok, settle(state)}
  end

  def handle_call({:remove, track_id}, _from, state) do
    {removed, queue} = Enum.split_with(state.queue, &(&1.id == track_id))
    Enum.each(removed, &delete_file/1)

    {:reply, :ok, settle(%{state | queue: queue})}
  end

  @impl true
  def handle_info({:ended, track_id}, %{current: %{id: track_id}} = state),
    do: {:noreply, state |> advance() |> settle()}

  # A song that was skipped right as it ended
  def handle_info({:ended, _track_id}, state), do: {:noreply, state}

  def handle_info({ref, result}, state) when is_map_key(state.tasks, ref) do
    Process.demonitor(ref, [:flush])
    {job, tasks} = Map.pop(state.tasks, ref)

    {:noreply, %{state | tasks: tasks} |> finish(job, result) |> settle()}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.tasks, ref) do
    {job, tasks} = Map.pop(state.tasks, ref)
    Logger.error("Music task crashed", event: "music_task_crashed", error: inspect(reason))

    {:noreply, %{state | tasks: tasks} |> finish(job, {:error, :unknown}) |> settle()}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run_task(state, job, fun) do
    task = Task.Supervisor.async_nolink(Botchini.Screens.JukeboxTasks, fun)
    put_in(state.tasks[task.ref], job)
  end

  defp finish(state, {:lookup, track_id, pid}, result) do
    case {find_track(state, track_id), result} do
      # Removed by an admin while it was looked up
      {nil, _result} ->
        state

      {track, {:ok, %{duration_ms: duration_ms} = video}}
      when is_integer(duration_ms) and duration_ms <= @max_duration_ms ->
        Activity.record(state.guild_id, :song_added, track.added_by, video.title)

        update_track(state, track_id, fn track ->
          %{
            track
            | title: video.title,
              url: video.url,
              thumbnail: video.thumbnail,
              duration_ms: duration_ms,
              status: :queued
          }
        end)

      {track, result} ->
        reason =
          case result do
            {:ok, %{duration_ms: nil}} -> :live
            {:ok, _video} -> :too_long
            {:error, reason} -> reason
          end

        Logger.info("Couldn't add a song", event: "music_add_failed", reason: reason)
        send(pid, {:music, {:add_failed, track.title, reason}})
        remove_track(state, track_id)
    end
  end

  defp finish(state, {:download, track_id}, result) do
    case {find_track(state, track_id), result} do
      {nil, {:ok, path}} ->
        File.rm(path)
        state

      {nil, {:error, _reason}} ->
        state

      {_track, {:ok, path}} ->
        update_track(state, track_id, &%{&1 | status: :ready, file: path})

      {track, {:error, reason}} ->
        Logger.warning("Couldn't download a song",
          event: "music_download_failed",
          reason: reason,
          track_title: track.title,
          url: track.url
        )

        Activity.record(state.guild_id, :song_failed, track.added_by, track.title)
        remove_track(state, track_id)
    end
  end

  # Brings everything in line after any change: the next song starts when there's
  # none, the songs about to play are downloaded, the others' files are dropped,
  # and the clock runs while a downloaded song isn't paused
  defp settle(state) do
    state
    |> take_next()
    |> start_downloads()
    |> drop_files()
    |> run_clock()
    |> broadcast()
  end

  # The queue keeps its order, so it waits for its first song to be looked up
  defp take_next(%{current: nil, queue: [%{status: status} = next | queue]} = state)
       when status != :looking_up,
       do: put_current(%{state | queue: queue}, next)

  defp take_next(state), do: state

  defp start_downloads(state) do
    dir = state.dir

    [state.current | Enum.take(state.queue, 1)]
    |> Enum.filter(&match?(%{status: :queued}, &1))
    |> Enum.reduce(state, fn track, state ->
      state
      |> run_task({:download, track.id}, fn -> download(track, dir) end)
      |> update_track(track.id, &%{&1 | status: :downloading})
    end)
  end

  defp download(track, dir) do
    case YtDlp.download(track.url, dir, track.id) do
      {:error, reason} when reason in @retried_downloads ->
        YtDlp.download(track.url, dir, track.id)

      result ->
        result
    end
  end

  # The song before, the one playing and the next one are kept, so going back
  # or forward is quick
  defp drop_files(state) do
    keep =
      [List.first(state.history), state.current, List.first(state.queue)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)

    update_tracks(state, fn
      %{status: :ready} = track ->
        if track.id in keep, do: track, else: delete_file(track)

      track ->
        track
    end)
  end

  defp delete_file(%{status: :ready} = track) do
    File.rm(track.file)
    %{track | status: :queued, file: nil}
  end

  defp delete_file(track), do: track

  defp run_clock(state) do
    state =
      cond do
        running?(state) and is_nil(state.started_at) ->
          %{state | started_at: now()}

        not running?(state) and is_integer(state.started_at) ->
          %{state | offset_ms: position(state), started_at: nil}

        true ->
          state
      end

    if state.timer, do: Process.cancel_timer(state.timer)

    timer =
      if running?(state) do
        left_ms = max(state.current.duration_ms - position(state), 0)
        Process.send_after(self(), {:ended, state.current.id}, left_ms + @end_grace_ms)
      end

    %{state | timer: timer}
  end

  defp running?(%{current: %{status: :ready}, paused?: false}), do: true
  defp running?(_state), do: false

  defp position(%{started_at: nil, offset_ms: offset_ms}), do: offset_ms
  defp position(state), do: state.offset_ms + now() - state.started_at

  defp advance(state) do
    history = Enum.take([state.current | state.history], @max_history)
    put_current(%{state | history: history}, nil)
  end

  # Picking a song plays it from the start, even if the last one was paused
  defp put_current(state, track),
    do: %{state | current: track, paused?: false, offset_ms: 0, started_at: nil}

  defp tracks(state), do: Enum.reject([state.current | state.queue ++ state.history], &is_nil/1)

  defp find_track(state, track_id), do: Enum.find(tracks(state), &(&1.id == track_id))

  defp update_track(state, track_id, fun),
    do: update_tracks(state, &if(&1.id == track_id, do: fun.(&1), else: &1))

  defp update_tracks(state, fun) do
    %{
      state
      | current: state.current && fun.(state.current),
        queue: Enum.map(state.queue, fun),
        history: Enum.map(state.history, fun)
    }
  end

  # A song that couldn't play is dropped, even the one playing
  defp remove_track(%{current: %{id: track_id}} = state, track_id), do: put_current(state, nil)

  defp remove_track(state, track_id) do
    reject = &Enum.reject(&1, fn track -> track.id == track_id end)
    %{state | queue: reject.(state.queue), history: reject.(state.history)}
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(
      Botchini.PubSub,
      topic(state.guild_id),
      {:music, {:state, public(state)}}
    )

    state
  end

  defp public(state) do
    %{
      current: state.current && public_track(state.current),
      queue: Enum.map(state.queue, &public_track/1),
      paused?: state.paused?,
      playing?: running?(state),
      # It goes a bit past the end while a song gets its moment to finish
      position_ms: min(position(state), (state.current && state.current.duration_ms) || 0),
      previous?: state.current != nil or state.history != []
    }
  end

  defp public_track(track), do: Map.delete(track, :file)

  defp now, do: System.monotonic_time(:millisecond)

  # 128 bits of randomness, as songs' audio is served to whoever has their id
  defp random_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
