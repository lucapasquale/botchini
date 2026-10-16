defmodule BotchiniWeb.ScreenLive.Video do
  @moduledoc """
  The guild page's menu for showing a YouTube video, or a YouTube or Twitch live
  stream, as one of its screens. Everyone watches it together, like a screen
  share, and anyone adds one, pauses it, skips through a video or stops it. The
  guild page calls `mount/3`, passes its `video:` events here, and its
  `{:restream, message}` messages
  """

  use BotchiniWeb, :html

  import Phoenix.LiveView, only: [connected?: 1]
  import BotchiniWeb.ScreenLive.Components, only: [bar_button: 1, bar_icon: 1, bar_panel_class: 0]

  alias Botchini.Screens.Restream

  @errors %{
    unsupported_url: "Only YouTube and Twitch links can be shown",
    already_showing: "A video is already being shown, stop it first",
    not_found: "Nothing found at that link",
    stream_offline: "That channel isn't live right now",
    age_restricted: "That video is age-restricted",
    unavailable: "That video is unavailable",
    timeout: "The video took too long to start, try again"
  }

  @doc """
  Starts following what the guild's page shows, for `user` to add links as
  """
  @spec mount(Phoenix.LiveView.Socket.t(), String.t(), %{id: String.t(), name: String.t()}) ::
          Phoenix.LiveView.Socket.t()
  def mount(socket, guild_id, user) do
    if connected?(socket), do: Restream.subscribe(guild_id)

    assign(socket,
      video_guild_id: guild_id,
      video_user: user,
      video: Restream.state(guild_id),
      video_error: nil
    )
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event("video:start", %{"url" => url}, socket) when is_binary(url) do
    case Restream.start(socket.assigns.video_guild_id, url, socket.assigns.video_user) do
      :ok -> assign(socket, video_error: nil)
      {:error, :blank} -> socket
      {:error, reason} -> assign(socket, video_error: error(reason))
    end
  end

  def handle_event("video:stop", _params, socket) do
    Restream.stop(socket.assigns.video_guild_id, socket.assigns.video_user)
    socket
  end

  def handle_event("video:pause", _params, socket) do
    Restream.pause(socket.assigns.video_guild_id, socket.assigns.video_user)
    socket
  end

  def handle_event("video:resume", _params, socket) do
    Restream.resume(socket.assigns.video_guild_id)
    socket
  end

  def handle_event("video:seek", %{"position_ms" => position_ms}, socket)
      when is_integer(position_ms) do
    Restream.seek(socket.assigns.video_guild_id, position_ms)
    socket
  end

  def handle_event(_event, _params, socket), do: socket

  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle_info({:state, state}, socket), do: assign(socket, video: state)

  def handle_info({:failed, reason}, socket), do: assign(socket, video_error: error(reason))

  defp error(reason),
    do: Map.get(@errors, reason, "Couldn't show that video, try again in a moment")

  attr :video, :map, default: nil
  attr :error, :string, default: nil

  @doc """
  The menu as a button of the bar, which opens it above the bar. The button is
  filled while a video is shown
  """
  def menu(assigns) do
    assigns =
      assign(assigns,
        bar_panel_class: bar_panel_class(),
        max_url_length: Restream.max_url_length()
      )

    ~H"""
    <div id="video-menu">
      <.bar_button
        id="video-toggle"
        title={if @video, do: "Video: #{@video.title}", else: "Show a video"}
        panel="video-panel"
        aria-pressed={to_string(@video != nil)}
      >
        <.bar_icon name={:tv} />
      </.bar_button>

      <div id="video-panel" data-popover hidden class={@bar_panel_class}>
        <h2 class="border-b border-gray-700 px-3 py-2 text-sm font-semibold">Show a video</h2>
        <div class="min-h-0 flex-1 space-y-3 overflow-y-auto p-3 text-sm">
          <div :if={@video} id="video-now" class="space-y-2">
            <div class="min-w-0">
              <a
                id="video-title"
                href={@video.url}
                target="_blank"
                rel="noopener noreferrer"
                class="line-clamp-2 font-semibold hover:underline"
              >
                {@video.title}
              </a>
              <p class="truncate text-xs text-gray-400">
                Added by {@video.added_by} · <span id="video-status">{status(@video.status)}</span>
              </p>
            </div>
            <button
              type="button"
              id="video-stop"
              phx-click="video:stop"
              class="w-full rounded-lg bg-gray-700 px-3 py-1.5 font-semibold transition hover:bg-red-600"
            >
              Stop
            </button>
          </div>

          <form :if={!@video} id="video-form" phx-submit="video:start" class="flex gap-1.5">
            <input
              id="video-input"
              name="url"
              type="url"
              autocomplete="off"
              maxlength={@max_url_length}
              placeholder="YouTube or Twitch link"
              aria-label="Link to show"
              class="min-w-0 flex-1 rounded-lg border border-gray-700 bg-gray-800 px-3 py-1.5 text-sm text-white placeholder:text-gray-500 focus:border-indigo-400 focus:outline-none"
            />
            <button
              type="submit"
              class="shrink-0 rounded-lg bg-indigo-600 px-3 py-1.5 font-semibold text-white transition hover:bg-indigo-500"
            >
              Show
            </button>
          </form>
          <p :if={@error} id="video-error" class="text-xs text-amber-400">{@error}</p>

          <p class="text-xs text-gray-500">
            Shows a YouTube video or a YouTube or Twitch live stream as a screen, at the same
            moment for everyone on the page. Anyone can pause it or skip through a video from
            its controls, or stop it here. One can be shown at a time, and it stops when the video ends.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp status(:looking_up), do: "Looking it up..."
  defp status(:starting), do: "Starting..."
  defp status(:live), do: "Showing"
  defp status(:paused), do: "Paused"
end
