defmodule BotchiniWeb.ScreenLive.Guild do
  @moduledoc """
  Page where members watch every screen being shared in a guild at once
  """

  use BotchiniWeb, :live_view

  import BotchiniWeb.ScreenLive.Components

  alias Botchini.Screens
  alias Botchini.Screens.Room

  @token_salt "screens guild"
  @token_max_age 86_400

  @spec sign_token(String.t()) :: String.t()
  def sign_token(guild_id), do: Phoenix.Token.sign(BotchiniWeb.Endpoint, @token_salt, guild_id)

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, page_title: "Screen shares", rooms: [])

    with true <- connected?(socket),
         {:ok, guild_id} <- verify_token(get_connect_params(socket)["key"]) do
      Screens.subscribe_guild(guild_id)
      rooms = guild_id |> Screens.list_rooms() |> Enum.filter(& &1.live?)

      {:ok, assign(socket, status: :open, rooms: rooms)}
    else
      false -> {:ok, assign(socket, status: :connecting)}
      {:error, _reason} -> {:ok, assign(socket, status: :not_found)}
    end
  end

  defp verify_token(token) when is_binary(token),
    do: Phoenix.Token.verify(BotchiniWeb.Endpoint, @token_salt, token, max_age: @token_max_age)

  defp verify_token(_token), do: {:error, :missing}

  @impl true
  def render(%{status: :connecting} = assigns) do
    ~H"""
    <.notice title="Connecting...">Looking for screen shares.</.notice>
    """
  end

  def render(%{status: :not_found} = assigns) do
    ~H"""
    <.notice title="Link expired">
      The link is invalid or expired. Run <code>/stream list</code> on Discord to get a new one!
    </.notice>
    """
  end

  def render(%{rooms: []} = assigns) do
    ~H"""
    <.notice title="Nobody is sharing their screen right now">
      Screen shares show up here as soon as they go live.
    </.notice>
    """
  end

  def render(assigns) do
    ~H"""
    <div class={["grid gap-6", length(@rooms) > 1 && "lg:grid-cols-2"]}>
      <div :for={room <- @rooms} id={"screen-#{room.id}"}>
        <div class="flex flex-wrap items-center justify-between gap-2 mb-2">
          <div class="min-w-0">
            <h2 class="truncate font-semibold">{room.title}</h2>
            <p class="text-sm text-gray-400">Shared by {room.owner_name}</p>
          </div>

          <div class="flex items-center gap-3 text-sm">
            <span class="text-gray-400">{viewers(room.viewer_count)}</span>
            <.link navigate={~p"/screens/#{room.id}"} class="text-indigo-400 hover:underline">
              Open
            </.link>
          </div>
        </div>

        <.viewer room={room} />
      </div>
    </div>

    <p class="mt-4 text-sm text-gray-500">
      Streams start muted, use the video controls to turn the sound on.
    </p>
    """
  end

  @impl true
  def handle_event("offer", %{"room_id" => room_id} = offer, socket) do
    with true <- watching?(socket, room_id),
         {:ok, answer} <- Room.watch(room_id, Map.delete(offer, "room_id")) do
      {:reply, %{answer: answer}, socket}
    else
      {:error, :full} -> {:reply, %{error: "This screen share is full"}, socket}
      _error -> {:reply, %{error: "Couldn't connect to the screen share"}, socket}
    end
  end

  def handle_event("ice_candidate", %{"room_id" => room_id} = candidate, socket) do
    if watching?(socket, room_id),
      do: Room.add_ice_candidate(room_id, Map.delete(candidate, "room_id"))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:screens, room_id, {:ice_candidate, candidate}}, socket) do
    {:noreply, push_event(socket, "screen:#{room_id}:ice_candidate", candidate)}
  end

  def handle_info({:screens, room_id, :reconnect}, socket) do
    {:noreply, push_event(socket, "screen:#{room_id}:reconnect", %{})}
  end

  def handle_info({:screen_room, :ended, room}, socket) do
    {:noreply, update(socket, :rooms, &Enum.reject(&1, fn r -> r.id == room.id end))}
  end

  def handle_info({:screen_room, _event, room}, socket) do
    {:noreply, update(socket, :rooms, &put_room(&1, room))}
  end

  defp put_room(rooms, room) do
    cond do
      Enum.any?(rooms, &(&1.id == room.id)) ->
        Enum.map(rooms, &if(&1.id == room.id, do: room, else: &1))

      room.live? ->
        Enum.sort_by(rooms ++ [room], & &1.started_at, DateTime)

      true ->
        rooms
    end
  end

  defp watching?(socket, room_id), do: Enum.any?(socket.assigns.rooms, &(&1.id == room_id))
end
