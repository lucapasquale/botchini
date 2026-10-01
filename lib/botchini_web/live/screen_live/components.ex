defmodule BotchiniWeb.ScreenLive.Components do
  @moduledoc """
  Components shared by the screen sharing pages
  """

  use BotchiniWeb, :html

  import Phoenix.LiveView, only: [push_event: 3]

  alias Botchini.Screens

  attr :room, :map, required: true
  slot :inner_block, doc: "Overlays shown on top of the video"

  def viewer(assigns) do
    ~H"""
    <div
      id={"screen-viewer-#{@room.id}"}
      phx-hook="ScreenViewer"
      data-room-id={@room.id}
      data-ice-servers={ice_servers_json()}
      class="relative aspect-video w-full overflow-hidden rounded-lg bg-black"
    >
      <video
        id={"screen-viewer-video-#{@room.id}"}
        phx-update="ignore"
        data-pointer-stream={@room.id}
        class="h-full w-full"
        autoplay
        muted
        playsinline
        controls
      ></video>

      <%!-- With the pointer on, clicks and drags over the picture are for drawing, and
        would otherwise pause the stream. The video's controls stay reachable below --%>
      <div data-pointer-shield class="absolute inset-x-0 top-0 bottom-12 hidden" aria-hidden="true">
      </div>

      <div
        :if={!@room.live?}
        class="absolute inset-0 flex items-center justify-center bg-black/80 p-2 text-center text-sm text-gray-300"
      >
        Waiting for {@room.owner_name} to start sharing...
      </div>

      <span
        id={"screen-viewer-status-#{@room.id}"}
        phx-update="ignore"
        data-screen-status
        class="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 rounded bg-black/70 px-2 py-1 text-center text-sm text-red-400 empty:hidden"
      ></span>

      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block

  def notice(assigns) do
    ~H"""
    <div class="py-24 text-center">
      <h1 class="text-2xl font-semibold mb-2">{@title}</h1>
      <p class="text-gray-400">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  attr :room_id, :string, required: true
  attr :class, :any, default: nil

  @doc """
  Ends the screen share for everyone. Only shown to admins, and checked again when clicked
  """
  def close_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="close"
      phx-value-room_id={@room_id}
      data-confirm="Close this screen share for everyone?"
      title="Close for everyone"
      class={["rounded p-1.5", @class]}
    >
      <span class="sr-only">Close for everyone</span>
      <svg
        class="h-4 w-4"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        aria-hidden="true"
      >
        <path d="M6 6l12 12M18 6L6 18" />
      </svg>
    </button>
    """
  end

  # Each member gets one of these colors, the same on every page and in every chat line
  @user_colors [
    {"bg-sky-400", "text-sky-300"},
    {"bg-pink-400", "text-pink-300"},
    {"bg-emerald-400", "text-emerald-300"},
    {"bg-orange-400", "text-orange-300"},
    {"bg-violet-400", "text-violet-300"},
    {"bg-cyan-400", "text-cyan-300"},
    {"bg-lime-400", "text-lime-300"},
    {"bg-rose-400", "text-rose-300"}
  ]

  @doc """
  Color of a member, as a background for their avatar or as a text color for their name
  """
  @spec user_color(String.t(), :bg | :text) :: String.t()
  def user_color(user_id, kind) do
    {bg, text} = Enum.at(@user_colors, :erlang.phash2(user_id, length(@user_colors)))
    if kind == :bg, do: bg, else: text
  end

  # How many avatars the online button shows before it only counts
  @max_avatars 5

  attr :users, :list,
    required: true,
    doc: "Members with the page open, as `%{id, name, admin?}`"

  attr :current_user_id, :string, required: true

  @doc """
  Members that have one of the server's screen sharing pages open right now, as a
  button with their avatars that opens the list. Admins get their own color.
  Anyone can mute the others' sounds and pointers, just for themselves, which the
  OnlineMutes hook keeps in the browser
  """
  def online(assigns) do
    assigns = assign(assigns, avatars: Enum.take(assigns.users, @max_avatars))

    ~H"""
    <div data-pointer-menu class="relative shrink-0">
      <button
        type="button"
        id="online-toggle"
        data-popover-toggle
        aria-controls="online-list"
        aria-expanded="false"
        title="Who's online"
        class="flex items-center gap-2 rounded-full bg-gray-800 py-1 pl-1 pr-3 text-xs font-semibold transition hover:bg-gray-700 aria-expanded:ring-2 aria-expanded:ring-indigo-400"
      >
        <span class="flex" aria-hidden="true">
          <span
            :for={user <- @avatars}
            class={[
              "-ml-1.5 grid h-6 w-6 place-items-center rounded-full text-[11px] font-bold text-gray-950 ring-2 ring-gray-800 first:ml-0",
              user_color(user.id, :bg)
            ]}
          >
            {initial(user.name)}
          </span>
        </span>
        {length(@users)} online
      </button>

      <section
        id="online-list"
        aria-label="Online"
        phx-hook="OnlineMutes"
        data-popover
        hidden
        class="absolute right-0 top-full z-50 mt-2 max-h-[60dvh] w-64 overflow-y-auto rounded-lg border border-gray-700 bg-gray-900/95 p-2 shadow-2xl"
      >
        <h2 class="px-2 pb-1.5 pt-1 text-xs font-semibold text-gray-400">
          Online · {length(@users)}
        </h2>

        <ul class="flex flex-col gap-1">
          <li
            :for={user <- @users}
            id={"online-#{user.id}"}
            title={if user.admin?, do: "Admin"}
            class={[
              "flex items-center gap-2 rounded-md px-2 py-1 text-sm",
              if(user.admin?, do: "bg-amber-500/20 text-amber-300", else: "hover:bg-gray-800")
            ]}
          >
            <span
              class={[
                "grid h-6 w-6 shrink-0 place-items-center rounded-full text-[11px] font-bold text-gray-950",
                user_color(user.id, :bg)
              ]}
              aria-hidden="true"
            >
              {initial(user.name)}
            </span>
            <span class="min-w-0 flex-1 truncate">
              {user.name}<span :if={user.admin?} class="sr-only"> (admin)</span><span
                :if={user.id == @current_user_id}
                class="text-gray-500"
              > (you)</span>
            </span>
            <span :if={user.id != @current_user_id} class="flex shrink-0 items-center">
              <button
                :for={{kind, icon, what} <- [{"sounds", "🔊", "sounds"}, {"pointer", "✨", "pointer"}]}
                type="button"
                data-mute-user={user.id}
                data-mute={kind}
                data-name={user.name}
                aria-pressed="false"
                title={"Mute #{user.name}'s #{what}"}
                class="rounded-full px-1 text-xs opacity-70 transition hover:bg-white/10 hover:opacity-100 aria-pressed:bg-red-500/30 aria-pressed:opacity-100"
              >
                {icon}
              </button>
            </span>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  defp initial(name), do: name |> String.first() |> Kernel.||("?") |> String.upcase()

  attr :title, :string, required: true
  attr :panel, :string, default: nil, doc: "Id of the popover the button opens, if any"
  attr :rest, :global
  slot :inner_block, required: true

  @doc """
  Icon button of the bar under the screens. It's filled while what it controls
  is on, with `aria-pressed`, and ringed while the popover it opens is open
  """
  def bar_button(assigns) do
    ~H"""
    <button
      type="button"
      title={@title}
      data-popover-toggle={@panel && true}
      aria-controls={@panel}
      aria-expanded={@panel && "false"}
      class="group relative grid h-9 w-9 place-items-center rounded-lg text-gray-400 transition hover:bg-gray-800 hover:text-white aria-pressed:bg-indigo-600 aria-pressed:text-white aria-pressed:hover:bg-indigo-500 aria-expanded:ring-2 aria-expanded:ring-indigo-300"
      {@rest}
    >
      <span class="sr-only">{@title}</span>
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :name, :atom, required: true
  attr :class, :any, default: nil

  @doc """
  Outline icons of the bar, drawn on a 24px grid
  """
  def bar_icon(assigns) do
    ~H"""
    <svg
      class={["h-5 w-5", @class]}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      {icon_paths(@name)}
    </svg>
    """
  end

  defp icon_paths(:sound) do
    assigns = %{}

    ~H"""
    <path d="M11 5 6 9H2v6h4l5 4V5Z" /><path d="M15.5 8.5a5 5 0 0 1 0 7M19 5a10 10 0 0 1 0 14" />
    """
  end

  defp icon_paths(:muted) do
    assigns = %{}

    ~H"""
    <path d="M11 5 6 9H2v6h4l5 4V5Z" /><path d="m22 9-6 6M16 9l6 6" />
    """
  end

  defp icon_paths(:pen) do
    assigns = %{}

    ~H"""
    <path d="M12 20h9" /><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
    """
  end

  defp icon_paths(:chat) do
    assigns = %{}

    ~H"""
    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z" />
    """
  end

  defp icon_paths(:megaphone) do
    assigns = %{}

    ~H"""
    <path d="m3 11 18-5v12L3 14v-3z" /><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6" />
    """
  end

  defp icon_paths(:send) do
    assigns = %{}

    ~H"""
    <path d="m22 2-7 20-4-9-9-4Z" /><path d="M22 2 11 13" />
    """
  end

  @doc """
  Discord ids are numbers, anything else can't be a guild
  """
  @spec parse_guild_id(term()) :: {:ok, String.t()} | :invalid
  def parse_guild_id(guild_id) when is_binary(guild_id) do
    if Regex.match?(~r/\A\d{1,20}\z/, guild_id), do: {:ok, guild_id}, else: :invalid
  end

  def parse_guild_id(_missing), do: :invalid

  def guild_not_found(assigns) do
    ~H"""
    <.notice title="Server not found">
      Open <strong>Watch all</strong>
      on Discord, or run <code>/stream watch</code>
      there to get the link.
    </.notice>
    """
  end

  attr :status, :atom, values: [:not_member, :unavailable], required: true

  def denied(%{status: :not_member} = assigns) do
    ~H"""
    <.notice title="Not in this server">
      Screen shares are only for members of the server. Log in with the Discord account you use there.
    </.notice>
    """
  end

  def denied(%{status: :unavailable} = assigns) do
    ~H"""
    <.notice title="Couldn't check your access">
      Discord isn't answering right now, try again in a moment.
    </.notice>
    """
  end

  @doc """
  Has the browser chime when viewers come and go, with a different sound for each.
  Only meant for the page of whoever is sharing the screen
  """
  @spec push_viewer_chime(Phoenix.LiveView.Socket.t(), non_neg_integer(), non_neg_integer()) ::
          Phoenix.LiveView.Socket.t()
  def push_viewer_chime(socket, before, now) when now > before,
    do: push_event(socket, "screen:viewer_joined", %{})

  def push_viewer_chime(socket, before, now) when now < before,
    do: push_event(socket, "screen:viewer_left", %{})

  def push_viewer_chime(socket, _before, _now), do: socket

  @doc """
  STUN/TURN servers the browsers use to find a route to the server
  """
  @spec ice_servers_json() :: String.t()
  def ice_servers_json, do: Jason.encode!(Screens.config()[:ice_servers])
end
