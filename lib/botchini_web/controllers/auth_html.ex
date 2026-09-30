defmodule BotchiniWeb.AuthHTML do
  @moduledoc """
  Pages rendered by AuthController
  """
  use BotchiniWeb, :html

  import BotchiniWeb.ScreenLive.Components, only: [notice: 1]

  attr :return_to, :string, required: true
  attr :error, :string, default: nil

  def login(assigns) do
    ~H"""
    <.notice title="Log in to watch">
      Screen shares are only for members of the server, log in with Discord to continue.
      <span :if={@error} class="mt-3 block text-red-400">{@error}</span>
      <a
        href={~p"/auth/discord?#{[return_to: @return_to]}"}
        class="mt-6 inline-block rounded bg-indigo-600 px-4 py-2 font-semibold text-white hover:bg-indigo-500"
      >
        Log in with Discord
      </a>
    </.notice>
    """
  end
end
