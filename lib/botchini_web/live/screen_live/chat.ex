defmodule BotchiniWeb.ScreenLive.Chat do
  @moduledoc """
  Chat of the guild page. Its lines float over the main screen, mixing what
  members say with what happened on the server's screen sharing pages, like who
  joined or which sound was played. Members can hide it, and then see how many
  messages they missed. The LiveView calls `mount/3`, and passes its `chat:`
  events and `{:screen_activity, event}` messages here
  """

  use BotchiniWeb, :html

  import Phoenix.LiveView, only: [connected?: 1]
  import BotchiniWeb.ScreenLive.Components, only: [bar_button: 1, bar_icon: 1, user_color: 2]

  alias Botchini.Screens.Activity
  alias BotchiniWeb.ScreenLive.ActivityFeed

  # Lines over the screen, the older ones fading out
  @shown 6
  @faded 3

  @doc """
  Starts listening to the guild's chat and activity, with the latest lines from
  before the page opened. `user` is who writes the page's messages
  """
  @spec mount(Phoenix.LiveView.Socket.t(), String.t(), %{id: String.t(), name: String.t()}) ::
          Phoenix.LiveView.Socket.t()
  def mount(socket, guild_id, user) do
    events =
      if connected?(socket) do
        # Subscribing first, so nothing said meanwhile is missed
        Activity.subscribe(guild_id)
        guild_id |> Activity.list() |> Enum.take(@shown)
      else
        []
      end

    assign(socket,
      chat_guild_id: guild_id,
      chat_user: user,
      chat_events: events,
      chat_open?: true,
      chat_unread: 0,
      chat_limiter: Activity.new_limiter(),
      chat_limited?: false
    )
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event("chat:send", %{"text" => text}, socket) when is_binary(text) do
    case Activity.hit(socket.assigns.chat_limiter, now()) do
      {:ok, limiter} ->
        Activity.say(socket.assigns.chat_guild_id, socket.assigns.chat_user, text)
        assign(socket, chat_limiter: limiter, chat_limited?: false)

      :limited ->
        assign(socket, chat_limited?: true)
    end
  end

  def handle_event("chat:toggle", _params, socket),
    do: assign(socket, chat_open?: !socket.assigns.chat_open?, chat_unread: 0)

  def handle_event(_event, _params, socket), do: socket

  @spec handle_info({:screen_activity, Activity.event()}, Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_info({:screen_activity, event}, socket) do
    # An event can be in the list already if it happened while mounting
    if Enum.any?(socket.assigns.chat_events, &(&1.id == event.id)) do
      socket
    else
      socket
      |> assign(chat_events: Enum.take([event | socket.assigns.chat_events], @shown))
      |> count_unread(event)
    end
  end

  # Only messages from the others count as missed, not events or one's own messages
  defp count_unread(%{assigns: %{chat_open?: false}} = socket, %{kind: :message} = event) do
    if event.actor_id == socket.assigns.chat_user.id,
      do: socket,
      else: assign(socket, chat_unread: socket.assigns.chat_unread + 1)
  end

  defp count_unread(socket, _event), do: socket

  attr :events, :list, required: true, doc: "Newest first"
  attr :limited?, :boolean, required: true
  attr :class, :any, default: nil

  @doc """
  The latest lines, oldest at the top, and the box to write a message. Only the
  box takes clicks, so members can still draw on the screen under the lines
  """
  def overlay(assigns) do
    assigns =
      assign(assigns, lines: assigns.events |> Enum.reverse() |> Enum.with_index(), faded: @faded)

    ~H"""
    <section
      id="chat"
      aria-label="Chat"
      class={["pointer-events-none z-10 flex w-full flex-col gap-1.5 sm:w-80", @class]}
    >
      <ol id="chat-lines" aria-live="polite" class="flex flex-col items-start gap-1 sm:items-end">
        <li
          :for={{event, index} <- @lines}
          id={"chat-#{event.id}"}
          class={[
            "max-w-full break-words rounded-lg bg-gray-950/75 px-2.5 py-1 backdrop-blur-sm transition-opacity",
            if(event.kind == :message, do: "text-sm", else: "text-xs text-gray-400"),
            index < length(@lines) - @faded && "opacity-50"
          ]}
        >
          <%= if event.kind == :message do %>
            <span class={["font-semibold", user_color(event.actor_id, :text)]}>{event.actor}</span>
            {event.detail}
          <% else %>
            <span aria-hidden="true">{ActivityFeed.icon(event.kind)}</span>
            {ActivityFeed.describe(event)}
          <% end %>
        </li>
      </ol>

      <form
        id="chat-form"
        phx-submit="chat:send"
        phx-hook="ChatForm"
        data-pointer-menu
        class="pointer-events-auto flex gap-1.5"
      >
        <input
          id="chat-input"
          name="text"
          type="text"
          autocomplete="off"
          maxlength={Activity.max_message_length()}
          placeholder="Message everyone watching"
          aria-label="Chat message"
          class="min-w-0 flex-1 rounded-lg border border-white/10 bg-gray-950/75 px-3 py-1.5 text-sm text-white placeholder:text-gray-500 backdrop-blur-sm focus:border-indigo-400 focus:outline-none"
        />
        <button
          type="submit"
          title="Send"
          class="grid w-9 shrink-0 place-items-center rounded-lg bg-indigo-600 text-white transition hover:bg-indigo-500"
        >
          <span class="sr-only">Send</span>
          <.bar_icon name={:send} class="h-4 w-4" />
        </button>
      </form>

      <p :if={@limited?} class="self-start rounded bg-gray-950/75 px-2 py-0.5 text-xs text-amber-400">
        Slow down, you can send more messages in a few seconds.
      </p>
    </section>
    """
  end

  attr :open?, :boolean, required: true
  attr :unread, :integer, required: true

  @doc """
  Shows or hides the chat, counting what was missed while it's hidden
  """
  def toggle_button(assigns) do
    ~H"""
    <.bar_button
      id="chat-toggle"
      title={if @open?, do: "Hide chat", else: "Show chat"}
      phx-click="chat:toggle"
      aria-pressed={to_string(@open?)}
    >
      <.bar_icon name={:chat} />
      <span
        :if={!@open? and @unread > 0}
        id="chat-unread"
        class="absolute -right-1 -top-1 min-w-4 rounded-full bg-red-500 px-1 text-[10px] font-bold leading-4 text-white"
      >
        {min(@unread, 99)}
      </span>
    </.bar_button>
    """
  end

  defp now, do: System.monotonic_time(:millisecond)
end
