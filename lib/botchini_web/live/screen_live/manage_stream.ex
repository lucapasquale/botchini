defmodule BotchiniWeb.ScreenLive.ManageStream do
  @moduledoc """
  Controls on the guild page for sharing your own screen, like the broadcast page
  but for logged in members. It's a LiveView of its own inside the guild page, as a
  room talks to one process per peer, and the page's process is already watching.
  The room is only made once the member picks something to share
  """

  use BotchiniWeb, :live_view

  import BotchiniWeb.ScreenLive.Components, only: [ice_servers_json: 0]

  alias Botchini.Screens
  alias Botchini.Screens.Room

  @impl true
  def mount(_params, %{"guild_id" => guild_id, "user" => user}, socket) do
    room = if connected?(socket), do: Screens.find_owner_room(guild_id, user.id)
    if room, do: Screens.subscribe(room.id)

    {:ok, assign(socket, guild_id: guild_id, user: user, room: room, pending_title: "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <p :if={obs?(@room)} class="text-sm text-gray-400">
      You're sharing from OBS. Stop that stream to share your screen from here.
    </p>

    <div :if={!obs?(@room)}>
      <%!-- The title and buttons on the left, what's being shared on the right. On
        phones the preview goes below them --%>
      <div
        id="screen-broadcast"
        phx-hook="ScreenBroadcast"
        data-ice-servers={ice_servers_json()}
        class="grid items-start gap-4 sm:grid-cols-2"
      >
        <div>
          <form
            id="manage-stream-title"
            phx-change="title"
            phx-submit="title"
            class="mb-3 flex items-center gap-2"
          >
            <label for="manage-stream-title-input" class="text-sm text-gray-400">Title</label>
            <input
              id="manage-stream-title-input"
              name="title"
              value={title_value(@room, @pending_title)}
              placeholder={Room.default_title(@user.name, room_source(@room))}
              maxlength="100"
              autocomplete="off"
              phx-debounce="blur"
              class="w-full rounded bg-gray-800 px-3 py-1.5 text-gray-200"
            />
          </form>

          <div
            id="screen-broadcast-controls"
            phx-update="ignore"
            class="flex flex-wrap items-center gap-3"
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
        To share sound, use Chrome or Edge, pick a browser tab or your entire screen (on Windows)
        and turn on audio sharing in the picker. Firefox can't share sound. Closing this tab ends
        your stream.
      </p>
    </div>
    """
  end

  defp obs?(%Room{source: :obs, live?: true}), do: true
  defp obs?(_room), do: false

  defp room_source(%Room{source: source}), do: source
  defp room_source(nil), do: :screen

  defp source("browser"), do: :tab
  defp source("window"), do: :window
  defp source(_surface), do: :screen

  defp title_value(%Room{custom_title?: true, title: title}, _pending), do: title
  defp title_value(%Room{}, _pending), do: nil
  defp title_value(nil, pending), do: pending

  @impl true
  def handle_event("source", %{"surface" => surface}, socket) do
    case ensure_room(socket) do
      {:ok, socket} ->
        Room.set_source(socket.assigns.room.id, source(surface))
        {:noreply, socket}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("offer", offer, socket) do
    with {:ok, socket} <- ensure_room(socket),
         {:ok, answer} <- Room.publish(socket.assigns.room.id, offer) do
      {:reply, %{answer: answer}, socket}
    else
      _error -> {:reply, %{error: "Couldn't start the screen share"}, socket}
    end
  end

  def handle_event("ice_candidate", candidate, %{assigns: %{room: %Room{} = room}} = socket) do
    Room.add_ice_candidate(room.id, candidate)
    {:noreply, socket}
  end

  def handle_event("ice_candidate", _candidate, socket), do: {:noreply, socket}

  def handle_event("title", %{"title" => title}, %{assigns: %{room: %Room{} = room}} = socket)
      when is_binary(title) do
    Room.set_title(room.id, title)
    {:noreply, socket}
  end

  # Kept until the room exists, where it's applied
  def handle_event("title", %{"title" => title}, socket) when is_binary(title),
    do: {:noreply, assign(socket, pending_title: String.slice(title, 0, 100))}

  def handle_event("stop", _params, %{assigns: %{room: %Room{} = room}} = socket) do
    Screens.stop_room(room)
    {:noreply, socket}
  end

  def handle_event("stop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:screens, _room_id, {:ice_candidate, candidate}}, socket) do
    {:noreply, push_event(socket, "screen:ice_candidate", candidate)}
  end

  def handle_info({:screen_room, :ended, room}, socket) do
    if socket.assigns.room && socket.assigns.room.id == room.id do
      Screens.unsubscribe(room.id)
      {:noreply, socket |> assign(room: nil) |> push_event("screen:ended", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:screen_room, _event, room}, socket) do
    if socket.assigns.room && socket.assigns.room.id == room.id,
      do: {:noreply, assign(socket, room: room)},
      else: {:noreply, socket}
  end

  # Room events this page doesn't care about, like the activity or the announcements
  def handle_info(_message, socket), do: {:noreply, socket}

  # The member picked something to share, so there's a room to put it in. Someone who
  # is already sharing gets their room back, and it has no channel to announce in, as
  # the page they're on shows it already
  defp ensure_room(%{assigns: %{room: %Room{}}} = socket), do: {:ok, socket}

  defp ensure_room(%{assigns: %{user: user, guild_id: guild_id}} = socket) do
    attrs = %{
      title: Room.default_title(user.name, :screen),
      guild_id: guild_id,
      channel_id: nil,
      owner_id: user.id,
      owner_name: user.name
    }

    case Screens.start_room(attrs) do
      {:ok, room} ->
        Screens.subscribe(room.id)

        if socket.assigns.pending_title != "",
          do: Room.set_title(room.id, socket.assigns.pending_title)

        {:ok, assign(socket, room: room)}

      {:error, _reason} ->
        {:error, socket}
    end
  end
end
