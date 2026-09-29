defmodule BotchiniWeb.ScreenLive.Broadcast do
  @moduledoc """
  Page where the owner of a room shares their screen. The broadcast key comes from
  the URL fragment through the socket connect params, so it's only checked once connected
  """

  use BotchiniWeb, :live_view

  import BotchiniWeb.ScreenLive.Components

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias BotchiniWeb.ScreenLive.{Guild, Soundboard}

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    socket = assign(socket, page_title: "Share your screen", room: nil)

    if connected?(socket) do
      broadcast_key = get_connect_params(socket)["key"]

      case Screens.get_room_for_broadcast(room_id, broadcast_key) do
        nil ->
          {:ok, assign(socket, status: :not_found)}

        room ->
          Screens.subscribe(room.id)

          {:ok,
           socket
           |> assign(
             room: room,
             status: :open,
             page_title: room.title,
             watch_url: nil
           )
           |> Soundboard.mount(room.guild_id)}
      end
    else
      {:ok, assign(socket, status: :connecting)}
    end
  end

  @impl true
  def render(%{status: :connecting} = assigns) do
    ~H"""
    <.notice title="Connecting...">Getting your screen share ready.</.notice>
    """
  end

  def render(%{status: :not_found} = assigns) do
    ~H"""
    <.notice title="Screen share not found">
      The link is invalid or the screen share ended. Run <code>/stream start</code>
      on Discord to get a new one!
    </.notice>
    """
  end

  def render(%{status: :ended} = assigns) do
    ~H"""
    <.notice title="Screen share ended">
      Thanks for sharing! Run <code>/stream start</code> on Discord to share again.
    </.notice>
    """
  end

  def render(assigns) do
    ~H"""
    <.room_header room={@room} />

    <form
      id="screen-title"
      phx-change="title"
      phx-submit="title"
      class="mb-4 flex items-center gap-2"
    >
      <label for="screen-title-input" class="text-sm text-gray-400">Title</label>
      <input
        id="screen-title-input"
        name="title"
        value={if @room.custom_title?, do: @room.title}
        placeholder={Room.default_title(@room.owner_name, @room.source)}
        maxlength="100"
        autocomplete="off"
        phx-debounce="blur"
        class="w-full max-w-md rounded bg-gray-800 px-3 py-1.5 text-gray-200"
      />
    </form>

    <div
      :if={@watch_url}
      class="mb-4 rounded-lg border border-amber-500/50 bg-amber-500/10 px-4 py-3 text-sm text-amber-200"
    >
      I couldn't post the watch link on Discord, probably because I'm not allowed to send
      messages in that channel. Share this link with your friends instead:
      <a href={@watch_url} class="break-all font-semibold underline">{@watch_url}</a>
    </div>

    <div
      id="screen-broadcast"
      phx-hook="ScreenBroadcast"
      data-ice-servers={ice_servers_json()}
    >
      <div
        id="screen-broadcast-controls"
        phx-update="ignore"
        class="flex flex-wrap items-center gap-3 mb-4"
      >
        <button
          data-screen-start
          class="rounded-lg bg-indigo-600 px-4 py-2 font-semibold text-white hover:bg-indigo-500"
        >
          Share screen
        </button>
        <button
          data-screen-switch
          hidden
          class="rounded-lg bg-gray-700 px-4 py-2 font-semibold hover:bg-gray-600"
        >
          Switch screen or window
        </button>
        <button
          data-screen-stop
          hidden
          class="rounded-lg bg-red-600 px-4 py-2 font-semibold text-white hover:bg-red-500"
        >
          Stop sharing
        </button>

        <span data-screen-status class="text-sm text-gray-400"></span>
        <span data-screen-audio hidden class="basis-full text-sm text-amber-400"></span>
      </div>

      <video
        id="screen-broadcast-preview"
        phx-update="ignore"
        class="aspect-video w-full rounded-lg bg-black"
        autoplay
        muted
        playsinline
      ></video>
    </div>

    <p class="mt-2 text-sm text-gray-500">
      Only people with the watch link can see your screen. To share sound, use Chrome or Edge,
      pick a browser tab or your entire screen (on Windows) and turn on audio sharing in the
      picker. Firefox can't share sound.
    </p>

    <Soundboard.soundboard cooldown?={@sounds_cooldown?} cooldown_message={@sounds_cooldown_message} />
    """
  end

  @impl true
  def handle_event("offer", offer, socket) do
    case Room.publish(socket.assigns.room.id, offer) do
      {:ok, answer} -> {:reply, %{answer: answer}, socket}
      {:error, _reason} -> {:reply, %{error: "Couldn't start the screen share"}, socket}
    end
  end

  def handle_event("ice_candidate", candidate, socket) do
    Room.add_ice_candidate(socket.assigns.room.id, candidate)
    {:noreply, socket}
  end

  def handle_event("title", %{"title" => title}, socket) when is_binary(title) do
    Room.set_title(socket.assigns.room.id, title)
    {:noreply, socket}
  end

  def handle_event("source", %{"surface" => surface}, socket) do
    Room.set_source(socket.assigns.room.id, source(surface))
    {:noreply, socket}
  end

  def handle_event("stop", _params, socket) do
    Screens.stop_room(socket.assigns.room)
    {:noreply, socket}
  end

  def handle_event("sound:" <> _action = event, params, socket),
    do: {:noreply, Soundboard.handle_event(event, params, socket)}

  @impl true
  def handle_info({:soundboard, message}, socket),
    do: {:noreply, Soundboard.handle_info(message, socket)}

  def handle_info({:screens, _room_id, {:ice_candidate, candidate}}, socket) do
    {:noreply, push_event(socket, "screen:ice_candidate", candidate)}
  end

  def handle_info({:screen_announcement_failed, _room_id}, socket) do
    {:noreply, assign(socket, watch_url: Guild.watch_url(socket.assigns.room.guild_id))}
  end

  def handle_info({:screen_room, :ended, room}, socket) do
    {:noreply, socket |> assign(room: room, status: :ended) |> push_event("screen:ended", %{})}
  end

  def handle_info({:screen_room, _event, room}, socket) do
    {:noreply, assign(socket, room: room, page_title: room.title)}
  end

  defp source("browser"), do: :tab
  defp source("window"), do: :window
  defp source(_surface), do: :screen
end
