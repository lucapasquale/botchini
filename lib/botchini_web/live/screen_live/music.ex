defmodule BotchiniWeb.ScreenLive.Music do
  @moduledoc """
  Music player of the guild page, playing songs from YouTube for everyone on it.
  Its button in the bar opens the song playing, its controls and the queue,
  where anyone adds songs and admins remove them. The Music hook plays the audio
  where the jukebox says the song is. The guild page calls `mount/3`, and passes
  its `music:` events and `{:music, message}` messages here
  """

  use BotchiniWeb, :html

  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]
  import BotchiniWeb.ScreenLive.Components, only: [bar_button: 1, bar_icon: 1, bar_panel_class: 0]

  alias Botchini.Screens.Jukebox

  @add_errors %{
    full: "The queue is full, wait for a few songs to play",
    not_found: "Nothing found on YouTube for that",
    unsupported_url: "Only YouTube links can be added",
    live: "Live streams can't be added",
    too_long: "Songs can be up to an hour long",
    age_restricted: "That video is age-restricted",
    unavailable: "That video is unavailable"
  }

  @doc """
  Starts listening to the guild's music, as `user`
  """
  @spec mount(Phoenix.LiveView.Socket.t(), String.t(), %{id: String.t(), name: String.t()}) ::
          Phoenix.LiveView.Socket.t()
  def mount(socket, guild_id, user) do
    if connected?(socket), do: Jukebox.subscribe(guild_id)

    socket
    |> assign(music_guild_id: guild_id, music_user: user, music_error: nil)
    |> put_state(Jukebox.state(guild_id))
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event("music:add", %{"term" => term}, socket) when is_binary(term) do
    case Jukebox.add(socket.assigns.music_guild_id, term, socket.assigns.music_user) do
      :ok -> assign(socket, music_error: nil)
      {:error, :blank} -> socket
      {:error, reason} -> assign(socket, music_error: add_error(reason, term))
    end
  end

  def handle_event("music:toggle", _params, socket) do
    Jukebox.toggle(socket.assigns.music_guild_id)
    socket
  end

  def handle_event("music:next", _params, socket) do
    Jukebox.next(socket.assigns.music_guild_id, socket.assigns.music_user.name)
    socket
  end

  def handle_event("music:previous", _params, socket) do
    Jukebox.previous(socket.assigns.music_guild_id)
    socket
  end

  def handle_event(_event, _params, socket), do: socket

  @doc """
  Takes a song out of the queue. The guild page checks it's an admin asking
  """
  @spec remove(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def remove(socket, %{"track" => track_id}) when is_binary(track_id) do
    Jukebox.remove(socket.assigns.music_guild_id, track_id)
    socket
  end

  def remove(socket, _params), do: socket

  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle_info({:state, state}, socket), do: put_state(socket, state)

  def handle_info({:add_failed, term, reason}, socket),
    do: assign(socket, music_error: add_error(reason, term))

  # The page shows the songs, and its hook plays the one playing from where it is
  defp put_state(socket, %{current: current} = state) do
    src =
      if current && current.status == :ready,
        do: ~p"/screens/#{socket.assigns.music_guild_id}/music/#{current.id}"

    socket
    |> assign(music: state)
    |> push_event("music:sync", %{
      track: current && current.id,
      src: src,
      playing: state.playing?,
      position: state.position_ms,
      duration: current && current.duration_ms
    })
  end

  defp add_error(reason, term),
    do: Map.get(@add_errors, reason, "Couldn't add \"#{term}\", try again in a moment")

  attr :state, :map, required: true
  attr :error, :string, default: nil
  attr :admin?, :boolean, required: true

  @doc """
  The player as a button of the bar under the screens, which opens it above the
  bar. The button is filled while a song plays
  """
  def menu(assigns) do
    assigns =
      assign(assigns,
        current: assigns.state.current,
        bar_panel_class: bar_panel_class(),
        max_term_length: Jukebox.max_term_length()
      )

    ~H"""
    <div id="music" phx-hook="Music">
      <audio id="music-audio" phx-update="ignore" preload="auto"></audio>

      <.bar_button
        id="music-toggle"
        title={if @current, do: "Music: #{@current.title}", else: "Music"}
        panel="music-panel"
        aria-pressed={to_string(@state.playing?)}
      >
        <.bar_icon name={:music} />
      </.bar_button>

      <div id="music-panel" data-popover hidden class={[@bar_panel_class, "sm:w-96"]}>
        <h2 class="border-b border-gray-700 px-3 py-2 text-sm font-semibold">Music</h2>
        <div class="min-h-0 flex-1 space-y-4 overflow-y-auto p-3 text-sm">
          <section id="music-now" aria-label="Now playing">
            <div :if={@current} class="flex gap-3">
              <img
                src={@current.thumbnail}
                alt=""
                class="aspect-video w-28 shrink-0 rounded bg-gray-800 object-cover"
              />
              <div class="min-w-0">
                <a
                  id="music-title"
                  href={@current.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="line-clamp-2 font-semibold hover:underline"
                >
                  {@current.title}
                </a>
                <p class="truncate text-xs text-gray-400">Added by {@current.added_by}</p>
                <p :if={@current.status != :ready} class="text-xs text-amber-400">Loading...</p>
              </div>
            </div>

            <p :if={!@current} class="text-gray-400">
              Nothing playing. Add a song from YouTube below.
            </p>

            <div :if={@current} class="mt-3">
              <div
                id="music-progress"
                phx-update="ignore"
                class="h-1.5 overflow-hidden rounded-full bg-gray-700"
              >
                <div data-music-progress class="h-full w-0 rounded-full bg-indigo-500"></div>
              </div>
              <div class="mt-1 flex justify-between text-xs tabular-nums text-gray-400">
                <span id="music-elapsed" phx-update="ignore" data-music-elapsed>0:00</span>
                <span>{format_duration(@current.duration_ms)}</span>
              </div>
            </div>

            <div class="mt-2 flex items-center justify-center gap-3">
              <button
                type="button"
                phx-click="music:previous"
                disabled={!@state.previous?}
                title="Previous"
                class="grid h-9 w-9 place-items-center rounded-full text-gray-300 transition hover:bg-gray-700 hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
              >
                <span class="sr-only">Previous</span>
                <.bar_icon name={:previous} />
              </button>
              <button
                type="button"
                id="music-play"
                phx-click="music:toggle"
                disabled={!@current}
                title={if @current && !@state.paused?, do: "Pause", else: "Play"}
                class="grid h-11 w-11 place-items-center rounded-full bg-indigo-600 text-white transition hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-40"
              >
                <span class="sr-only">{if @current && !@state.paused?, do: "Pause", else: "Play"}</span>
                <.bar_icon name={if @current && !@state.paused?, do: :pause, else: :play} />
              </button>
              <button
                type="button"
                phx-click="music:next"
                disabled={!@current}
                title="Next"
                class="grid h-9 w-9 place-items-center rounded-full text-gray-300 transition hover:bg-gray-700 hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
              >
                <span class="sr-only">Next</span>
                <.bar_icon name={:next} />
              </button>
            </div>
          </section>

          <%!-- Only for this page, so the hook keeps it --%>
          <div id="music-volume" phx-update="ignore">
            <div class="flex items-center gap-2">
              <button
                type="button"
                data-music-mute
                title="Mute music"
                class="rounded px-1.5 py-0.5 text-lg hover:bg-white/10"
              >
                🔊
              </button>
              <input
                data-music-volume
                type="range"
                min="0"
                max="1"
                step="0.05"
                value="0.5"
                aria-label="Music volume"
                class="min-w-0 flex-1"
              />
            </div>
            <p data-music-blocked hidden class="mt-1 text-sm text-amber-400">
              Click anywhere on the page to hear the music
            </p>
          </div>

          <form id="music-form" phx-submit="music:add" phx-hook="ChatForm" class="flex gap-1.5">
            <input
              id="music-input"
              name="term"
              type="text"
              autocomplete="off"
              maxlength={@max_term_length}
              placeholder="YouTube link or search"
              aria-label="Song to add"
              class="min-w-0 flex-1 rounded-lg border border-gray-700 bg-gray-800 px-3 py-1.5 text-sm text-white placeholder:text-gray-500 focus:border-indigo-400 focus:outline-none"
            />
            <button
              type="submit"
              class="shrink-0 rounded-lg bg-indigo-600 px-3 py-1.5 font-semibold text-white transition hover:bg-indigo-500"
            >
              Add
            </button>
          </form>
          <p :if={@error} id="music-error" class="-mt-2 text-xs text-amber-400">{@error}</p>

          <section id="music-queue" aria-label="Queue">
            <h3 class="mb-1.5 text-xs font-semibold uppercase tracking-wide text-gray-400">
              Up next · {length(@state.queue)}
            </h3>
            <p :if={@state.queue == []} class="text-gray-500">The queue is empty.</p>
            <ol class="space-y-1.5">
              <li
                :for={track <- @state.queue}
                id={"music-track-#{track.id}"}
                class="flex items-center gap-2 rounded-lg bg-gray-800 p-1.5"
              >
                <img
                  :if={track.thumbnail}
                  src={track.thumbnail}
                  alt=""
                  loading="lazy"
                  class="aspect-video w-16 shrink-0 rounded bg-gray-700 object-cover"
                />
                <div
                  :if={!track.thumbnail}
                  class="grid aspect-video w-16 shrink-0 place-items-center rounded bg-gray-700 text-gray-400"
                  aria-hidden="true"
                >
                  <.bar_icon name={:music} class="h-4 w-4" />
                </div>
                <div class="min-w-0 flex-1">
                  <p class="truncate font-semibold" title={track.title}>{track.title}</p>
                  <p class="truncate text-xs text-gray-400">
                    {track.added_by} · {if track.status == :looking_up,
                      do: "Looking up...",
                      else: format_duration(track.duration_ms)}
                  </p>
                </div>
                <button
                  :if={@admin?}
                  type="button"
                  phx-click="music:remove"
                  phx-value-track={track.id}
                  title={"Remove #{track.title} from the queue"}
                  class="shrink-0 rounded p-1.5 text-gray-400 transition hover:bg-red-600 hover:text-white"
                >
                  <span class="sr-only">Remove from the queue</span>
                  <.bar_icon name={:close} class="h-4 w-4" />
                </button>
              </li>
            </ol>
          </section>

          <p class="text-xs text-gray-500">
            Everyone on the server's page hears the same song. Anyone can add songs and skip
            them, and admins can remove them from the queue.
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  A song's length, as "3:07" or "1:02:45"
  """
  @spec format_duration(non_neg_integer() | nil) :: String.t()
  def format_duration(nil), do: "--:--"

  def format_duration(ms) do
    seconds = div(ms, 1_000)

    {hours, minutes, seconds} =
      {div(seconds, 3_600), div(rem(seconds, 3_600), 60), rem(seconds, 60)}

    pad = &String.pad_leading(Integer.to_string(&1), 2, "0")

    if hours > 0,
      do: "#{hours}:#{pad.(minutes)}:#{pad.(seconds)}",
      else: "#{minutes}:#{pad.(seconds)}"
  end
end
