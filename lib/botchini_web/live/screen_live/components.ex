defmodule BotchiniWeb.ScreenLive.Components do
  @moduledoc """
  Components shared by the screen sharing pages
  """

  use BotchiniWeb, :html

  alias Botchini.Screens

  attr :room, :map, required: true

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
      </div>
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

  @spec viewers(non_neg_integer()) :: String.t()
  def viewers(1), do: "1 viewer"
  def viewers(count), do: "#{count} viewers"

  @doc """
  STUN/TURN servers the browsers use to find a route to the server
  """
  @spec ice_servers_json() :: String.t()
  def ice_servers_json, do: Jason.encode!(Screens.config()[:ice_servers])
end
