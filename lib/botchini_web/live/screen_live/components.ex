defmodule BotchiniWeb.ScreenLive.Components do
  @moduledoc """
  Components shared by the screen sharing pages
  """

  use BotchiniWeb, :html

  alias Botchini.Screens

  attr :room, :map, required: true
  slot :inner_block, doc: "Actions shown next to the room's status"

  def room_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
      <div>
        <h1 class="text-2xl font-semibold">{@room.title}</h1>
        <p class="text-sm text-gray-400">Shared by {@room.owner_name}</p>
      </div>

      <div class="flex items-center gap-3 text-sm">
        <span :if={@room.live?} class="rounded bg-red-600 px-2 py-0.5 font-semibold text-white">
          LIVE
        </span>
        <span :if={!@room.live?} class="rounded bg-gray-700 px-2 py-0.5 font-semibold">
          OFFLINE
        </span>
        <span class="text-gray-400">
          {viewers(@room.viewer_count)}
        </span>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

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
        class="h-full w-full"
        autoplay
        muted
        playsinline
        controls
      ></video>

      <div
        :if={!@room.live?}
        class="absolute inset-0 flex items-center justify-center bg-black/80 text-gray-300"
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

  @spec viewers(non_neg_integer()) :: String.t()
  def viewers(1), do: "1 viewer"
  def viewers(count), do: "#{count} viewers"

  @doc """
  STUN/TURN servers the browsers use to find a route to the server
  """
  @spec ice_servers_json() :: String.t()
  def ice_servers_json, do: Jason.encode!(Screens.config()[:ice_servers])
end
