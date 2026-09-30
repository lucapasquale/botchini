defmodule BotchiniWeb.ScreenLive.Guild do
  @moduledoc """
  Page where members watch every screen being shared in a guild at once. Pinned
  screens take most of the page, and the others shrink to a strip below them
  """

  use BotchiniWeb, :live_view

  import BotchiniWeb.ScreenLive.Components

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias BotchiniWeb.Auth
  alias BotchiniWeb.ScreenLive.{ActivityFeed, Pointers, Soundboard}

  # Widths of the screens in rows of two and three, minus the gaps between them
  @half "lg:w-[calc(50%_-_0.5rem)]"
  @third "xl:w-[calc(33.333%_-_0.667rem)]"

  @doc """
  Link to this page for a guild. Anyone can know it, as only the guild's
  members get in
  """
  @spec watch_url(String.t()) :: String.t()
  def watch_url(guild_id), do: url(~p"/screens/#{guild_id}")

  @impl true
  def mount(params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Screen shares",
        rooms: [],
        pinned: MapSet.new(),
        online: [],
        admin?: false,
        full_width?: true
      )

    # Discord is only asked once connected, instead of for both renders
    with true <- connected?(socket),
         {:ok, guild_id} <- parse_guild_id(params["guild_id"]),
         access when access in [:member, :admin] <- Auth.member_status(socket, guild_id) do
      Screens.subscribe_guild(guild_id)
      # Subscribing first, so the page also hears about its own arrival
      Screens.subscribe_online(guild_id)
      Screens.track_online(guild_id, socket.assigns.current_user, access == :admin)

      {:ok,
       socket
       |> assign(
         status: :open,
         guild_id: guild_id,
         online: Screens.list_online(guild_id),
         admin?: access == :admin,
         rooms: guild_id |> Screens.list_rooms() |> Enum.filter(& &1.live?)
       )
       |> ActivityFeed.mount(guild_id)
       |> Soundboard.mount(guild_id, socket.assigns.current_user)
       |> Pointers.mount(guild_id, socket.assigns.current_user)}
    else
      false -> {:ok, assign(socket, status: :connecting)}
      :not_member -> {:ok, assign(socket, status: :not_member)}
      :error -> {:ok, assign(socket, status: :unavailable)}
      :invalid -> {:ok, assign(socket, status: :not_found)}
    end
  end

  # Discord ids are numbers, anything else can't be a guild
  defp parse_guild_id(guild_id) when is_binary(guild_id) do
    if Regex.match?(~r/\A\d{1,20}\z/, guild_id), do: {:ok, guild_id}, else: :invalid
  end

  defp parse_guild_id(_missing), do: :invalid

  @impl true
  def render(%{status: :connecting} = assigns) do
    ~H"""
    <.notice title="Connecting...">Looking for screen shares.</.notice>
    """
  end

  def render(%{status: status} = assigns) when status in [:not_member, :unavailable] do
    ~H"""
    <.denied status={@status} />
    """
  end

  def render(%{status: :not_found} = assigns) do
    ~H"""
    <.notice title="Server not found">
      Open <strong>Watch all</strong>
      on Discord, or run <code>/stream watch</code>
      there to get the link.
    </.notice>
    """
  end

  # The soundboard works without anyone sharing, for members hanging out on the page
  def render(%{rooms: []} = assigns) do
    ~H"""
    <.notice title="Nobody is sharing their screen right now">
      Screen shares show up here as soon as they go live.
    </.notice>

    <.online_list users={@online} current_user_id={@current_user.id} />
    <ActivityFeed.feed events={@activity} />

    <Soundboard.soundboard
      cooldown?={@sounds_cooldown?}
      cooldown_message={@sounds_cooldown_message}
      page_key={"guild:#{@guild_id}"}
    />
    """
  end

  # Pinning only changes the tiles' classes, never their place in the DOM, as
  # moving a video would remount its hook and restart the connection
  def render(assigns) do
    ~H"""
    <%!-- Rows are spaced with margins, as a row gap would also go around the row break --%>
    <div class="flex flex-wrap justify-center gap-x-4">
      <%!-- Starts a new row for the unpinned screens --%>
      <div :if={MapSet.size(@pinned) > 0} class="order-1 basis-full"></div>

      <div
        :for={room <- @rooms}
        id={"screen-#{room.id}"}
        class={["mb-4", tile_class(room, @rooms, @pinned)]}
      >
        <.viewer room={room}>
          <div class="pointer-events-none absolute inset-x-0 top-0 flex items-start justify-between gap-2 bg-gradient-to-b from-black/70 to-transparent p-2 text-sm">
            <div class="min-w-0">
              <p class="truncate font-semibold text-white">{room.title}</p>
              <p class="truncate text-xs text-gray-300">
                {room.owner_name} · {viewers(room.viewer_count)}
              </p>
            </div>

            <div class="pointer-events-auto flex shrink-0 items-center gap-1">
              <.close_button
                :if={@admin?}
                room_id={room.id}
                class="text-gray-200 hover:bg-red-600 hover:text-white"
              />

              <button
                type="button"
                phx-click="pin"
                phx-value-room_id={room.id}
                aria-pressed={to_string(room.id in @pinned)}
                title={if room.id in @pinned, do: "Unpin", else: "Pin"}
                class={[
                  "rounded p-1.5 hover:bg-white/20",
                  if(room.id in @pinned, do: "bg-indigo-600 text-white", else: "text-gray-200")
                ]}
              >
                <span class="sr-only">{if room.id in @pinned, do: "Unpin", else: "Pin"}</span>
                <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                  <path d="M16 3a1 1 0 0 1 .7 1.7L15 6.4v4.2l2.7 2.7a1 1 0 0 1-.7 1.7h-4v6a1 1 0 0 1-2 0v-6H7a1 1 0 0 1-.7-1.7L9 10.6V6.4L7.3 4.7A1 1 0 0 1 8 3h8Z" />
                </svg>
              </button>
            </div>
          </div>
        </.viewer>
      </div>
    </div>

    <p class="text-sm text-gray-500">
      Streams start muted, use the video controls to turn the sound on. Pin streams to watch
      them bigger.
    </p>

    <.online_list users={@online} current_user_id={@current_user.id} />
    <ActivityFeed.feed events={@activity} />

    <Soundboard.soundboard
      cooldown?={@sounds_cooldown?}
      cooldown_message={@sounds_cooldown_message}
      page_key={"guild:#{@guild_id}"}
    />
    """
  end

  defp tile_class(room, rooms, pinned) do
    if MapSet.size(pinned) == 0,
      do: grid_tile_class(length(rooms)),
      else: pinned_tile_class(room, pinned)
  end

  # With nothing pinned, every screen gets the same size
  defp grid_tile_class(1), do: "w-full md:max-w-[calc((100dvh_-_7rem)_*_16_/_9)]"
  defp grid_tile_class(count) when count <= 4, do: "w-full #{@half}"
  defp grid_tile_class(_count), do: "w-full #{@half} #{@third}"

  # Big screens are capped so they fit the window's height, leaving room for
  # the header and the strip of unpinned screens
  defp pinned_tile_class(room, pinned) do
    cond do
      room.id not in pinned ->
        "order-2 w-[calc(50%_-_0.5rem)] sm:w-56 lg:w-64"

      MapSet.size(pinned) == 1 ->
        "w-full md:max-w-[calc((100dvh_-_16rem)_*_16_/_9)]"

      MapSet.size(pinned) == 2 ->
        "w-full md:w-[calc(50%_-_0.5rem)] md:max-w-[calc((100dvh_-_16rem)_*_16_/_9)]"

      MapSet.size(pinned) <= 4 ->
        "w-full md:w-[calc(50%_-_0.5rem)] md:max-w-[calc((100dvh_-_17rem)_*_8_/_9)]"

      true ->
        "w-full md:w-[calc(50%_-_0.5rem)] #{@third} md:max-w-[calc((100dvh_-_17rem)_*_8_/_9)]"
    end
  end

  @impl true
  def handle_event("pin", %{"room_id" => room_id}, socket) do
    pinned = socket.assigns.pinned

    pinned =
      cond do
        room_id in pinned -> MapSet.delete(pinned, room_id)
        watching?(socket, room_id) -> MapSet.put(pinned, room_id)
        true -> pinned
      end

    {:noreply, assign(socket, pinned: pinned)}
  end

  # Admins' rights are checked again, as they can lose them while the page is open
  def handle_event("close", %{"room_id" => room_id}, socket) do
    with %Room{} = room <- Enum.find(socket.assigns.rooms, &(&1.id == room_id)),
         :admin <- Auth.member_status(socket, room.guild_id) do
      Screens.stop_room(room, :closed_by_admin)
      {:noreply, socket}
    else
      status when status in [:member, :not_member] -> {:noreply, assign(socket, admin?: false)}
      _unknown_room_or_error -> {:noreply, socket}
    end
  end

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

  def handle_event("sound:" <> _action = event, params, socket),
    do: {:noreply, Soundboard.handle_event(event, params, socket)}

  def handle_event("pointer:" <> _action = event, params, socket),
    do: {:noreply, Pointers.handle_event(event, params, socket)}

  @impl true
  def handle_info({:soundboard, message}, socket),
    do: {:noreply, Soundboard.handle_info(message, socket)}

  def handle_info({:pointers, message}, socket),
    do: {:noreply, Pointers.handle_info(message, socket)}

  def handle_info({:screen_activity, _event} = message, socket),
    do: {:noreply, ActivityFeed.handle_info(message, socket)}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, online: Screens.list_online(socket.assigns.guild_id))}
  end

  def handle_info({:screens, room_id, {:ice_candidate, candidate}}, socket) do
    {:noreply, push_event(socket, "screen:#{room_id}:ice_candidate", candidate)}
  end

  def handle_info({:screens, room_id, :reconnect}, socket) do
    {:noreply, push_event(socket, "screen:#{room_id}:reconnect", %{})}
  end

  def handle_info({:screen_room, :ended, room}, socket) do
    {:noreply,
     socket
     |> update(:rooms, &Enum.reject(&1, fn r -> r.id == room.id end))
     |> update(:pinned, &MapSet.delete(&1, room.id))}
  end

  def handle_info({:screen_room, _event, room}, socket) do
    {:noreply,
     socket
     |> chime_for_owner(room)
     |> update(:rooms, &put_room(&1, room))}
  end

  # Streamers hear their viewers come and go here too, which is the only place
  # they can hear it when streaming from OBS
  defp chime_for_owner(socket, room) do
    with true <- room.owner_id == socket.assigns.current_user.id,
         %Room{} = before <- Enum.find(socket.assigns.rooms, &(&1.id == room.id)) do
      push_viewer_chime(socket, before.viewer_count, room.viewer_count)
    else
      _not_owner_or_new_room -> socket
    end
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
