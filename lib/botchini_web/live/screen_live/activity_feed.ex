defmodule BotchiniWeb.ScreenLive.ActivityFeed do
  @moduledoc """
  Compact list of what happened lately on the guild's screen sharing pages. It's
  a single line with the latest event until opened. The LiveViews call `mount/2`,
  and pass the `{:screen_activity, event}` messages here
  """

  use BotchiniWeb, :html

  import Phoenix.LiveView, only: [connected?: 1]

  alias Botchini.Screens.Activity

  @max_events 50

  @doc """
  Starts listening to the guild's activity, with what happened before the page opened
  """
  @spec mount(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def mount(socket, guild_id) do
    if connected?(socket) do
      # Subscribing first, so nothing that happens meanwhile is missed
      Activity.subscribe(guild_id)
      assign(socket, activity: Activity.list(guild_id))
    else
      assign(socket, activity: [])
    end
  end

  @spec handle_info({:screen_activity, Activity.event()}, Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_info({:screen_activity, event}, socket) do
    # An event can be in the list already if it happened while mounting
    if Enum.any?(socket.assigns.activity, &(&1.id == event.id)),
      do: socket,
      else: assign(socket, activity: Enum.take([event | socket.assigns.activity], @max_events))
  end

  attr :events, :list, required: true, doc: "Newest first"

  def feed(assigns) do
    ~H"""
    <section id="activity" class="mt-4 text-xs text-gray-400">
      <button
        type="button"
        id="activity-toggle"
        aria-expanded="false"
        aria-controls="activity-list"
        phx-click={toggle()}
        class="flex w-full items-center gap-2 text-left hover:text-gray-200"
      >
        <span class="font-semibold">Activity</span>
        <span id="activity-latest" class="min-w-0 flex-1 truncate text-gray-500">
          {latest(@events)}
        </span>
        <svg
          class="h-3 w-3 shrink-0"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>

      <ol id="activity-list" hidden class="mt-2 max-h-40 space-y-1 overflow-y-auto">
        <li :for={event <- @events} id={"activity-#{event.id}"} class="flex gap-2">
          <%!-- The hook shows the time of the visitor's timezone, the server only knows UTC --%>
          <time
            id={"activity-time-#{event.id}"}
            phx-hook="LocalTime"
            datetime={DateTime.to_iso8601(event.at)}
            class="shrink-0 tabular-nums text-gray-500"
          >
            {Calendar.strftime(event.at, "%H:%M")}
          </time>
          <span class="shrink-0" aria-hidden="true">{icon(event.kind)}</span>
          <span class="min-w-0 truncate">{describe(event)}</span>
        </li>
        <li :if={@events == []} class="text-gray-500">Nothing happened yet.</li>
      </ol>
    </section>
    """
  end

  # Tailwind hides [hidden] with !important, which beats the inline display
  # JS.toggle/1 sets, so the attribute itself has to go
  defp toggle do
    %JS{}
    |> JS.toggle_attribute({"hidden", "hidden"}, to: "#activity-list")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#activity-toggle")
  end

  defp latest([]), do: "Nothing yet"
  defp latest([event | _older]), do: describe(event)

  @doc """
  Says what happened in a few words
  """
  @spec describe(Activity.event()) :: String.t()
  def describe(%{kind: :joined, actor: actor}), do: "#{actor} joined"
  def describe(%{kind: :left, actor: actor}), do: "#{actor} left"
  def describe(%{kind: :sound, actor: actor, detail: sound}), do: "#{actor} played #{sound}"
  def describe(%{kind: :sound_stopped, actor: actor}), do: "#{actor} stopped the sounds"
  def describe(%{kind: :stream_started, actor: actor}), do: "#{actor} started streaming"
  def describe(%{kind: :message, actor: actor, detail: text}), do: "#{actor}: #{text}"

  def describe(%{kind: :stream_ended, actor: actor, detail: nil}),
    do: "#{actor} stopped streaming"

  def describe(%{kind: :stream_ended, actor: actor, detail: detail}),
    do: "#{actor} stopped streaming (#{detail})"

  @doc """
  Emoji shown next to an event
  """
  @spec icon(Activity.kind()) :: String.t()
  def icon(:joined), do: "🟢"
  def icon(:left), do: "⚪"
  def icon(:sound), do: "🔊"
  def icon(:sound_stopped), do: "🔇"
  def icon(:stream_started), do: "🔴"
  def icon(:stream_ended), do: "⏹️"
  def icon(:message), do: "💬"
end
