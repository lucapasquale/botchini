defmodule BotchiniWeb.ScreenLive.Broadcast do
  @moduledoc """
  Page where the owner of a room shares their screen. The broadcast key comes from
  the URL fragment through the socket connect params, so it's only checked once connected
  """

  use BotchiniWeb, :live_view

  import BotchiniWeb.ScreenLive.Components

  alias Botchini.Screens
  alias Botchini.Screens.Room

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    socket = assign(socket, page_title: "Share your screen", room: nil)

    if connected?(socket) do
      broadcast_key = get_connect_params(socket)["broadcast_key"]

      case Screens.get_room_for_broadcast(room_id, broadcast_key) do
        nil ->
          {:ok, assign(socket, status: :not_found)}

        room ->
          Screens.subscribe(room.id)
          {:ok, assign(socket, room: room, status: :open, page_title: room.title)}
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
      The link is invalid or the screen share ended. Run <code>/screen start</code>
      on Discord to get a new one!
    </.notice>
    """
  end

  def render(%{status: :ended} = assigns) do
    ~H"""
    <.notice title="Screen share ended">
      Thanks for sharing! Run <code>/screen start</code> on Discord to share again.
    </.notice>
    """
  end

  def render(assigns) do
    ~H"""
    <.room_header room={@room} />

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

        <label class="flex items-center gap-2 text-sm text-gray-400">
          Optimize for
          <select data-screen-hint class="rounded bg-gray-800 px-2 py-1 text-gray-200">
            <option value="motion" selected>Motion (games, videos)</option>
            <option value="detail">Text and detail</option>
          </select>
        </label>

        <span data-screen-status class="text-sm text-gray-400"></span>
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
      Only people with the watch link can see your screen. To share sound, pick a browser
      tab or your entire screen (on Windows) and enable audio sharing.
    </p>
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

  def handle_event("stop", _params, socket) do
    Screens.stop_room(socket.assigns.room)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:screens, _room_id, {:ice_candidate, candidate}}, socket) do
    {:noreply, push_event(socket, "screen:ice_candidate", candidate)}
  end

  def handle_info({:screen_room, :ended, room}, socket) do
    {:noreply, socket |> assign(room: room, status: :ended) |> push_event("screen:ended", %{})}
  end

  def handle_info({:screen_room, _event, room}, socket) do
    {:noreply, assign(socket, room: room)}
  end
end
