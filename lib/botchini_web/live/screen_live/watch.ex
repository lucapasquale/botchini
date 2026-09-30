defmodule BotchiniWeb.ScreenLive.Watch do
  @moduledoc """
  Page where members watch a shared screen. The browser negotiates its WebRTC
  connection with the room through this LiveView
  """

  use BotchiniWeb, :live_view

  import BotchiniWeb.ScreenLive.Components

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias BotchiniWeb.Auth
  alias BotchiniWeb.ScreenLive.Soundboard

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    socket = assign(socket, room: nil, page_title: "Screen share")

    case Screens.get_room(room_id) do
      nil -> {:ok, assign(socket, status: :not_found)}
      room -> {:ok, open_room(socket, room)}
    end
  end

  defp open_room(socket, room) do
    case Auth.member_status(socket, room.guild_id) do
      :member ->
        if connected?(socket), do: Screens.subscribe(room.id)

        socket
        |> assign(room: room, status: :open, page_title: room.title)
        |> Soundboard.mount(room.guild_id)

      :not_member ->
        assign(socket, status: :not_member)

      :error ->
        assign(socket, status: :unavailable)
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

  def render(%{status: status} = assigns) when status in [:not_member, :unavailable] do
    ~H"""
    <.denied status={@status} />
    """
  end

  def render(%{status: :ended} = assigns) do
    ~H"""
    <.notice title="Screen share ended">
      {@room.owner_name} stopped sharing their screen.
    </.notice>

    <Soundboard.soundboard cooldown?={@sounds_cooldown?} cooldown_message={@sounds_cooldown_message} />
    """
  end

  def render(assigns) do
    ~H"""
    <.room_header room={@room} />

    <.viewer room={@room} />

    <p class="mt-2 text-sm text-gray-500">
      The stream starts muted, use the video controls to turn the sound on.
    </p>

    <Soundboard.soundboard cooldown?={@sounds_cooldown?} cooldown_message={@sounds_cooldown_message} />
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

  def handle_event("sound:" <> _action = event, params, socket),
    do: {:noreply, Soundboard.handle_event(event, params, socket)}

  @impl true
  def handle_info({:soundboard, message}, socket),
    do: {:noreply, Soundboard.handle_info(message, socket)}

  def handle_info({:screens, room_id, {:ice_candidate, candidate}}, socket) do
    {:noreply, push_event(socket, "screen:#{room_id}:ice_candidate", candidate)}
  end

  def handle_info({:screens, room_id, :reconnect}, socket) do
    {:noreply, push_event(socket, "screen:#{room_id}:reconnect", %{})}
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
