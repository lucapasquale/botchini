defmodule BotchiniWeb.ScreenLive.Guild do
  @moduledoc """
  Page where members watch the screens being shared in a guild. One screen takes
  most of the page, with the chat floating over it, and the others wait in a strip
  below it, next to the bar with the soundboard, the pointer and the chat's switch
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
        main_id: nil,
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
  # its hook and restart the connection, so a grid places them: the main one takes
  # the second row, and the others fill the third one's first columns, before the bar
  def render(assigns) do
    assigns = assign(assigns, main: main_room(assigns.rooms, assigns.main_id))

    ~H"""
    <div
      id="screens"
      phx-hook="Popovers"
      class="mx-auto grid w-full max-w-[calc((100dvh_-_16rem)_*_16_/_9)] gap-3"
      style={columns(@rooms)}
    >
      <div class="col-span-full row-start-1 flex min-w-0 items-center justify-between gap-3">
        <div id="watching" class="flex min-w-0 items-center gap-2.5">
          <%= if @main do %>
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
          <% else %>
            <h1 class="truncate text-base font-semibold">Screen shares</h1>
          <% end %>
        </div>

        <.online users={@online} current_user_id={@current_user.id} />
      </div>

      <div
        :for={room <- @rooms}
        id={"screen-#{room.id}"}
        data-main={to_string(room == @main)}
        class={["group min-w-0", tile_class(room == @main)]}
      >
        <.viewer room={room}>
          <button
            :if={room != @main}
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
            :if={@admin?}
            class="absolute right-1.5 top-1.5 z-20 opacity-0 transition group-hover:opacity-100 group-focus-within:opacity-100"
          >
            <.close_button
              room_id={room.id}
              class="bg-black/60 text-gray-200 hover:bg-red-600 hover:text-white"
            />
          </div>
        </.viewer>
      </div>

      <%!-- Takes the main screen's place, looking like a video that didn't start --%>
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
        class="col-span-full row-start-5 sm:row-start-2 sm:mb-14 sm:mr-3 sm:self-end sm:justify-self-end"
      />

      <div
        id="screen-bar"
        data-pointer-menu
        class="relative col-span-full row-start-4 flex items-center gap-1 self-center justify-self-end rounded-xl border border-gray-800 bg-gray-900 p-1 sm:col-[-2/-1] sm:row-start-3"
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

    <p
      :if={@rooms != []}
      class="mx-auto mt-3 max-w-[calc((100dvh_-_16rem)_*_16_/_9)] text-sm text-gray-500"
    >
      Streams start muted, use the video controls to turn the sound on. Click a stream under the
      big one to watch it instead.
    </p>
    """
  end

  # The strip gets a column per screen besides the main one, which shrink to fit
  # the bar. On phones the bar and the chat get rows of their own, below the strip
  defp columns(rooms) do
    case length(rooms) do
      count when count > 1 ->
        "grid-template-columns: repeat(#{count - 1}, minmax(0, 9rem)) minmax(0, 1fr) auto"

      _single_or_none ->
        "grid-template-columns: minmax(0, 1fr) auto"
    end
  end

  defp tile_class(true), do: "col-span-full row-start-2"
  defp tile_class(false), do: "row-start-3 self-center"

  # The screen members picked, or the one shared first
  defp main_room(rooms, main_id),
    do: Enum.find(rooms, List.first(rooms), &(&1.id == main_id))

  @impl true
  def handle_event("watch", %{"room_id" => room_id}, socket) do
    if watching?(socket, room_id),
      do: {:noreply, assign(socket, main_id: room_id)},
      else: {:noreply, socket}
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
     |> update(:main_id, &if(&1 == room.id, do: nil, else: &1))}
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
