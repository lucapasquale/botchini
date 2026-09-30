defmodule BotchiniWeb.ScreenLive.Pointers do
  @moduledoc """
  Relays the pointers of the guild's screen sharing pages. The LiveViews call
  `mount/3`, and pass their `pointer:` events and `{:pointers, message}` messages here
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]

  alias Botchini.Screens.Pointers

  @doc """
  Starts relaying the guild's pointers for `user`. Every page gets its own id, so
  the same member with two pages open shows two pointers instead of a jumpy one
  """
  @spec mount(Phoenix.LiveView.Socket.t(), String.t(), %{id: String.t(), name: String.t()}) ::
          Phoenix.LiveView.Socket.t()
  def mount(socket, guild_id, user) do
    if connected?(socket), do: Pointers.subscribe(guild_id)

    assign(socket,
      pointers_guild_id: guild_id,
      pointers_user: user,
      pointers_sender: 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false),
      pointers_limiter: Pointers.new_limiter()
    )
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event("pointer:move", params, socket) do
    with {:ok, move} <- Pointers.parse_move(params),
         {:ok, limiter} <- Pointers.hit_move(socket.assigns.pointers_limiter, now()) do
      relay(socket, :move, move)
      assign(socket, pointers_limiter: limiter)
    else
      _invalid_or_limited -> socket
    end
  end

  def handle_event("pointer:effect", params, socket) do
    with {:ok, effect} <- Pointers.parse_effect(params),
         {:ok, limiter} <- Pointers.hit_effect(socket.assigns.pointers_limiter, now()) do
      relay(socket, :effect, effect)
      assign(socket, pointers_limiter: limiter)
    else
      _invalid_or_limited -> socket
    end
  end

  def handle_event("pointer:off", _params, socket) do
    relay(socket, :off, %{})
    socket
  end

  def handle_event(_event, _params, socket), do: socket

  defp relay(socket, kind, payload) do
    %{id: user_id, name: name} = socket.assigns.pointers_user

    Pointers.broadcast(
      socket.assigns.pointers_guild_id,
      {kind, Map.merge(payload, %{s: socket.assigns.pointers_sender, u: user_id, n: name})}
    )
  end

  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle_info({kind, payload}, socket) when kind in [:move, :effect, :off],
    do: push_event(socket, "pointer:#{kind}", payload)

  def handle_info(_message, socket), do: socket

  defp now, do: System.monotonic_time(:millisecond)
end
