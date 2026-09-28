defmodule BotchiniWeb.ScreenLive.Watch do
  @moduledoc """
  Page where members watch a shared screen. The browser negotiates its WebRTC
  connection with the room through this LiveView
  """

  use BotchiniWeb, :live_view

  import BotchiniWeb.ScreenLive.Components

  alias Botchini.Screens
  alias Botchini.Screens.Room

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    case Screens.get_room(room_id) do
      nil ->
        {:ok, assign(socket, room: nil, status: :not_found, page_title: "Screen share")}

      room ->
        if connected?(socket), do: Screens.subscribe(room.id)
        {:ok, assign(socket, room: room, status: :open, page_title: room.title)}
    end
  end

  @impl true
  def render(%{status: :not_found} = assigns) do
    ~H"""
    <.notice title="Screen share not found">
      It may have ended already. Ask for a new link on Discord!
    </.notice>
    """
  end

  def render(%{status: :ended} = assigns) do
    ~H"""
    <.notice title="Screen share ended">
      {@room.owner_name} stopped sharing their screen.
    </.notice>
    """
  end

  def render(assigns) do
    ~H"""
    <.room_header room={@room} />

    <.viewer room={@room} />

    <p class="mt-2 text-sm text-gray-500">
      The stream starts muted, use the video controls to turn the sound on.
    </p>
    """
  end

  @impl true
  def handle_event("offer", offer, socket) do
    case Room.watch(socket.assigns.room.id, offer) do
      {:ok, answer} -> {:reply, %{answer: answer}, socket}
      {:error, :full} -> {:reply, %{error: "This screen share is full"}, socket}
      {:error, _reason} -> {:reply, %{error: "Couldn't connect to the screen share"}, socket}
    end
  end

  def handle_event("ice_candidate", candidate, socket) do
    Room.add_ice_candidate(socket.assigns.room.id, candidate)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:screens, room_id, {:ice_candidate, candidate}}, socket) do
    {:noreply, push_event(socket, "screen:#{room_id}:ice_candidate", candidate)}
  end

  def handle_info({:screen_announcement_failed, _room_id}, socket), do: {:noreply, socket}

  def handle_info({:screen_room, :ended, room}, socket) do
    {:noreply,
     socket |> assign(room: room, status: :ended) |> push_event("screen:#{room.id}:ended", %{})}
  end

  def handle_info({:screen_room, _event, room}, socket) do
    {:noreply, assign(socket, room: room, page_title: room.title)}
  end
end
