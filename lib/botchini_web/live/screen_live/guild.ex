defmodule BotchiniWeb.ScreenLive.Guild do
  @moduledoc """
  Page where members watch every screen being shared in a guild at once. Pinned
  screens take most of the page, and the others shrink to a strip below them
  """

  use BotchiniWeb, :live_view

  import BotchiniWeb.ScreenLive.Components

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias BotchiniWeb.ScreenLive.Soundboard

  @token_salt "screens guild"
  @token_max_age 86_400

  # Widths of the screens in rows of two and three, minus the gaps between them
  @half "lg:w-[calc(50%_-_0.5rem)]"
  @third "xl:w-[calc(33.333%_-_0.667rem)]"

  @doc """
  Signs a key for the guild's page. It expires after a day, unless a screen share
  that was running by then is still going, so links don't die mid-stream
  """
  @spec sign_token(String.t(), integer()) :: String.t()
  def sign_token(guild_id, signed_at \\ System.system_time(:second)) do
    # Phoenix.Token can't tell when a token was signed, so it's kept in the payload
    Phoenix.Token.sign(BotchiniWeb.Endpoint, @token_salt, {guild_id, signed_at})
  end

  @doc """
  Link to this page for a guild. Links to a single room are only shown here,
  so the token lives in the fragment, which browsers never send to the server
  """
  @spec watch_url(String.t()) :: String.t()
  def watch_url(guild_id), do: url(~p"/screens") <> "#" <> sign_token(guild_id)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Screen shares",
        rooms: [],
        pinned: MapSet.new(),
        full_width?: true
      )

    with true <- connected?(socket),
         {:ok, {guild_id, signed_at}} <- verify_token(get_connect_params(socket)["key"]),
         rooms = Screens.list_rooms(guild_id),
         false <- expired?(signed_at, rooms) do
      Screens.subscribe_guild(guild_id)

      {:ok,
       socket
       |> assign(status: :open, rooms: Enum.filter(rooms, & &1.live?))
       |> Soundboard.mount(guild_id)}
    else
      false -> {:ok, assign(socket, status: :connecting)}
      _invalid -> {:ok, assign(socket, status: :not_found)}
    end
  end

  defp verify_token(token) when is_binary(token),
    do: Phoenix.Token.verify(BotchiniWeb.Endpoint, @token_salt, token, max_age: :infinity)

  defp verify_token(_token), do: {:error, :missing}

  # Only rooms already open when the link expired keep it working, otherwise any
  # old link would work again as soon as someone starts sharing
  defp expired?(signed_at, rooms) do
    expires_at = DateTime.from_unix!(signed_at + @token_max_age)

    DateTime.after?(DateTime.utc_now(), expires_at) and
      not Enum.any?(rooms, &DateTime.before?(&1.started_at, expires_at))
  end

  @impl true
  def render(%{status: :connecting} = assigns) do
    ~H"""
    <.notice title="Connecting...">Looking for screen shares.</.notice>
    """
  end

  def render(%{status: :not_found} = assigns) do
    ~H"""
    <.notice title="Link expired">
      The link is invalid or expired. Run <code>/stream watch</code> on Discord to get a new one!
    </.notice>
    """
  end

  # The soundboard works without anyone sharing, for members hanging out on the page
  def render(%{rooms: []} = assigns) do
    ~H"""
    <.notice title="Nobody is sharing their screen right now">
      Screen shares show up here as soon as they go live.
    </.notice>

    <Soundboard.soundboard cooldown?={@sounds_cooldown?} cooldown_message={@sounds_cooldown_message} />
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

              <.link
                navigate={~p"/screens/#{room.id}"}
                title="Open on its own page"
                class="rounded p-1.5 text-gray-200 hover:bg-white/20"
              >
                <span class="sr-only">Open on its own page</span>
                <svg
                  class="h-4 w-4"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" />
                </svg>
              </.link>
            </div>
          </div>
        </.viewer>
      </div>
    </div>

    <p class="text-sm text-gray-500">
      Streams start muted, use the video controls to turn the sound on. Pin streams to watch
      them bigger.
    </p>

    <Soundboard.soundboard cooldown?={@sounds_cooldown?} cooldown_message={@sounds_cooldown_message} />
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

  @impl true
  def handle_info({:soundboard, message}, socket),
    do: {:noreply, Soundboard.handle_info(message, socket)}

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
