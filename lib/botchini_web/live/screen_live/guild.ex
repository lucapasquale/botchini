defmodule BotchiniWeb.ScreenLive.Guild do
  @moduledoc """
  Page where members watch the screens being shared in a guild. One screen takes
  most of the page, or several pinned ones share it, with the chat floating over
  them. The others wait in a strip below, next to the bar with the soundboard, the
  pointer and the chat's switch
  """

  use BotchiniWeb, :live_view

  import BotchiniWeb.ScreenLive.Components

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias BotchiniWeb.Auth
  alias BotchiniWeb.ScreenLive.{Chat, Pointers, Soundboard}

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
        pinned: [],
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
       |> Chat.mount(guild_id, socket.assigns.current_user)
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

  # The soundboard and the chat work without anyone sharing, for members hanging
  # out on the page. Screens never move in the DOM, as moving a video would remount
  # its hook and restart the connection, so a grid places them: the big ones take
  # the rows after the header, and the others fill the next one's first columns,
  # before the bar
  def render(assigns) do
    big = big_rooms(assigns.rooms, assigns.pinned)
    main = if length(big) == 1, do: hd(big)

    assigns = assign(assigns, big: big, main: main, layout: layout(length(big)))

    ~H"""
    <div
      id="screens"
      phx-hook="Popovers"
      class="mx-auto grid w-full gap-3"
      style={columns(length(@rooms) - length(@big)) <> rows(@layout) <> max_width(@layout)}
    >
      <div class="col-span-full row-start-1 flex min-w-0 items-center justify-between gap-3">
        <div id="watching" class="flex min-w-0 items-center gap-2.5">
          <%= cond do %>
            <% @main -> %>
              <span
                :if={@main.live?}
                class="shrink-0 rounded bg-red-600 px-1.5 py-0.5 text-[10px] font-bold tracking-wide text-white"
              >
                LIVE
              </span>
              <h1 class="truncate text-base font-semibold">{@main.title}</h1>
              <span class="hidden shrink-0 text-sm text-gray-400 sm:inline">
                Shared by {@main.owner_name}
              </span>
            <% @big != [] -> %>
              <h1 class="truncate text-base font-semibold">Watching {length(@big)} screens</h1>
            <% true -> %>
              <h1 class="truncate text-base font-semibold">Screen shares</h1>
          <% end %>
        </div>

        <.online users={@online} current_user_id={@current_user.id} />
      </div>

      <div
        :for={room <- @rooms}
        id={"screen-#{room.id}"}
        data-main={to_string(room in @big)}
        class={["group min-w-0", tile_class(room in @big)]}
        style={tile_style(room, @big, @layout)}
      >
        <.viewer room={room}>
          <span
            :if={@main == nil and room in @big}
            class="pointer-events-none absolute left-1.5 top-1.5 z-10 max-w-[calc(100%_-_5rem)] truncate rounded bg-black/70 px-1.5 py-0.5 text-xs font-semibold text-white"
          >
            {room.title} · {room.owner_name}
          </span>

          <button
            :if={room not in @big}
            type="button"
            phx-click="watch"
            phx-value-room_id={room.id}
            title={"Watch #{room.title}"}
            class="absolute inset-0 z-10 flex items-end rounded-lg p-1.5 text-left ring-indigo-400 transition hover:ring-2"
          >
            <span class="max-w-full truncate rounded bg-black/70 px-1.5 py-0.5 text-xs font-semibold text-white">
              {room.owner_name}
            </span>
          </button>

          <div
            :if={@admin? or room != @main}
            class="absolute right-1.5 top-1.5 z-20 flex gap-1 opacity-0 transition group-hover:opacity-100 group-focus-within:opacity-100"
          >
            <.pin_button :if={room != @main} room={room} pinned?={room in @big} />
            <.close_button
              :if={@admin?}
              room_id={room.id}
              class="bg-black/60 text-gray-200 hover:bg-red-600 hover:text-white"
            />
          </div>
        </.viewer>
      </div>

      <%!-- Takes the big screen's place, looking like a video that didn't start --%>
      <div
        :if={@rooms == []}
        id="no-screens"
        class="col-span-full row-start-2 grid aspect-video place-items-center rounded-lg bg-black px-6 text-center"
      >
        <div>
          <h2 class="mb-2 text-2xl font-semibold">Nobody is sharing their screen right now</h2>
          <p class="text-gray-400">Screen shares show up here as soon as they go live.</p>
        </div>
      </div>

      <%!-- Above the video's controls, which the browser draws at its bottom --%>
      <Chat.overlay
        :if={@chat_open?}
        events={@chat_events}
        limited?={@chat_limited?}
        class="col-span-full row-start-(--chat-row) sm:row-start-2 sm:row-end-(--strip-row) sm:mb-14 sm:mr-3 sm:self-end sm:justify-self-end"
      />

      <div
        id="screen-bar"
        data-pointer-menu
        class="relative col-span-full row-start-(--bar-row) flex items-center gap-1 self-center justify-self-end rounded-xl border border-gray-800 bg-gray-900 p-1 sm:col-[-2/-1] sm:row-start-(--strip-row)"
      >
        <Soundboard.sounds_menu
          cooldown?={@sounds_cooldown?}
          cooldown_message={@sounds_cooldown_message}
        />
        <Soundboard.pointer_menu page_key={"guild:#{@guild_id}"} />
        <span class="mx-0.5 h-6 w-px bg-gray-700" aria-hidden="true"></span>
        <Chat.toggle_button open?={@chat_open?} unread={@chat_unread} />
      </div>
    </div>

    <p :if={@rooms != []} class="mx-auto mt-3 text-sm text-gray-500" style={max_width(@layout)}>
      Streams start muted, use the video controls to turn the sound on. Click a stream under the
      big one to watch it instead, or pin it to keep both big.
    </p>
    """
  end

  attr :room, :map, required: true
  attr :pinned?, :boolean, required: true

  defp pin_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="pin"
      phx-value-room_id={@room.id}
      aria-pressed={to_string(@pinned?)}
      title={if @pinned?, do: "Unpin #{@room.title}", else: "Pin #{@room.title} to keep it big"}
      class="rounded bg-black/60 p-1.5 text-gray-200 hover:bg-white/20 hover:text-white aria-pressed:bg-indigo-600 aria-pressed:text-white aria-pressed:hover:bg-indigo-500"
    >
      <span class="sr-only">{if @pinned?, do: "Unpin", else: "Pin"}</span>
      <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M16 3a1 1 0 0 1 .7 1.7L15 6.4v4.2l2.7 2.7a1 1 0 0 1-.7 1.7h-4v6a1 1 0 0 1-2 0v-6H7a1 1 0 0 1-.7-1.7L9 10.6V6.4L7.3 4.7A1 1 0 0 1 8 3h8Z" />
      </svg>
    </button>
    """
  end

  # The strip gets a column per screen that isn't big, which shrink to fit the
  # bar. On phones the bar and the chat get rows of their own, below the strip
  defp columns(0), do: "grid-template-columns: minmax(0, 1fr) auto;"

  defp columns(strip_count),
    do: "grid-template-columns: repeat(#{strip_count}, minmax(0, 9rem)) minmax(0, 1fr) auto;"

  # How many big screens go in each row, and how many rows they take
  defp layout(count) when count <= 1, do: %{per_row: 1, rows: 1, count: 1}
  defp layout(count) when count <= 4, do: %{per_row: 2, rows: ceil(count / 2), count: count}
  defp layout(count), do: %{per_row: 3, rows: ceil(count / 3), count: count}

  # Rows of the strip, and of the bar and the chat on phones, after the big screens'
  defp rows(%{rows: rows}) do
    "--strip-row: #{rows + 2}; --bar-row: #{rows + 3}; --chat-row: #{rows + 4};"
  end

  # Big screens are capped so they fit the window's height, leaving room for the
  # header, the strip and the note below them
  defp max_width(%{per_row: per_row, rows: rows}) do
    height = "(100dvh - 16rem - #{rows - 1} * 0.75rem) / #{rows}"
    "max-width: calc(#{height} * 16 / 9 * #{per_row} + #{per_row - 1} * 0.75rem);"
  end

  defp tile_class(true), do: "col-span-full justify-self-start"
  defp tile_class(false), do: "row-start-(--strip-row) self-center"

  # Big screens in the same row share its cell, each moved over by the ones before
  # it. A row that isn't full is centered
  defp tile_style(room, big, %{per_row: per_row, count: count}) do
    case Enum.find_index(big, &(&1 == room)) do
      nil ->
        nil

      index ->
        row = div(index, per_row)
        in_row = min(per_row, count - row * per_row)
        offset = rem(index, per_row) + (per_row - in_row) / 2

        "grid-row-start: #{row + 2}; width: calc((100% - #{per_row - 1} * 0.75rem) / #{per_row}); " <>
          "margin-left: calc(#{offset} * (100% + 0.75rem) / #{per_row});"
    end
  end

  # The screens members pinned, or the one shared first
  defp big_rooms(rooms, pinned) do
    case Enum.flat_map(pinned, fn id -> Enum.filter(rooms, &(&1.id == id)) end) do
      [] -> Enum.take(rooms, 1)
      big -> big
    end
  end

  defp big_ids(socket) do
    socket.assigns.rooms |> big_rooms(socket.assigns.pinned) |> Enum.map(& &1.id)
  end

  @impl true
  def handle_event("watch", %{"room_id" => room_id}, socket) do
    if watching?(socket, room_id),
      do: {:noreply, assign(socket, pinned: [room_id])},
      else: {:noreply, socket}
  end

  # The last big screen stays, as there's always one
  def handle_event("pin", %{"room_id" => room_id}, socket) do
    big_ids = big_ids(socket)

    cond do
      not watching?(socket, room_id) -> {:noreply, socket}
      room_id not in big_ids -> {:noreply, assign(socket, pinned: big_ids ++ [room_id])}
      length(big_ids) > 1 -> {:noreply, assign(socket, pinned: big_ids -- [room_id])}
      true -> {:noreply, socket}
    end
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

  def handle_event("chat:" <> _action = event, params, socket),
    do: {:noreply, Chat.handle_event(event, params, socket)}

  @impl true
  def handle_info({:soundboard, message}, socket),
    do: {:noreply, Soundboard.handle_info(message, socket)}

  def handle_info({:pointers, message}, socket),
    do: {:noreply, Pointers.handle_info(message, socket)}

  def handle_info({:screen_activity, _event} = message, socket),
    do: {:noreply, Chat.handle_info(message, socket)}

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
     |> update(:pinned, &List.delete(&1, room.id))}
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
