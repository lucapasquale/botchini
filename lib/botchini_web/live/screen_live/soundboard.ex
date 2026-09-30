defmodule BotchiniWeb.ScreenLive.Soundboard do
  @moduledoc """
  Soundboard shown on the screen sharing pages. The LiveViews call `mount/2`, and
  pass their `sound:` events and `{:soundboard, message}` messages here
  """

  use BotchiniWeb, :html

  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]

  alias Botchini.Screens.{Activity, Sounds}

  # Shown while a member waits after playing too many sounds too fast
  @cooldown_messages [
    "Easy there, DJ! Give it a few seconds 🎧",
    "Spam detected. Go touch grass for 5 seconds 🌱",
    "Whoa, whoa, whoa. This isn't a rhythm game 🥁",
    "Even ultimates have a cooldown ⏳",
    "You've been nerfed. Try again in a sec 🔨",
    "Achievement unlocked: Most Annoying Viewer 🏆",
    "Chill, the buttons aren't going anywhere 🧊",
    "Our ears called. They asked for a break 👂",
    "Too much sauce. Let it simmer 🍝",
    "Button mashing won't win this one 🕹️"
  ]

  @doc """
  Starts listening to the guild's sounds. Each page counts its own sounds in a row,
  and the guild's activity says the sounds it plays were played by `actor`
  """
  @spec mount(Phoenix.LiveView.Socket.t(), String.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def mount(socket, guild_id, actor) do
    if connected?(socket), do: Sounds.subscribe(guild_id)

    assign(socket,
      sounds_guild_id: guild_id,
      sounds_actor: actor,
      sounds_limiter: Sounds.new_limiter(),
      sounds_cooldown?: false,
      sounds_cooldown_message: nil
    )
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event("sound:play", %{"sound" => sound_id}, socket) do
    with %{} = sound <- Sounds.get(sound_id),
         {:ok, limiter} <- Sounds.hit(socket.assigns.sounds_limiter, now()) do
      Sounds.play(socket.assigns.sounds_guild_id, sound)

      Activity.record(
        socket.assigns.sounds_guild_id,
        :sound,
        socket.assigns.sounds_actor,
        "#{sound.emoji} #{sound.name}"
      )

      socket = assign(socket, sounds_limiter: limiter)

      # Playing too fast starts the cooldown right away, not on the next click
      case Sounds.cooldown_left(limiter, now()) do
        0 -> socket
        left_ms -> start_cooldown(socket, left_ms)
      end
    else
      {:cooldown, left_ms} -> start_cooldown(socket, left_ms)
      nil -> socket
    end
  end

  def handle_event("sound:stop", _params, socket) do
    Sounds.stop(socket.assigns.sounds_guild_id)
    Activity.record(socket.assigns.sounds_guild_id, :sound_stopped, socket.assigns.sounds_actor)
    socket
  end

  def handle_event(_event, _params, socket), do: socket

  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle_info({:play, sound}, socket) do
    push_event(socket, "sound:play", %{
      id: sound.id,
      emoji: sound.emoji,
      url: sound_path(sound)
    })
  end

  def handle_info(:stop, socket), do: push_event(socket, "sound:stop", %{})

  def handle_info(:cooldown_over, socket) do
    case Sounds.cooldown_left(socket.assigns.sounds_limiter, now()) do
      0 -> assign(socket, sounds_cooldown?: false)
      left_ms -> start_cooldown(socket, left_ms)
    end
  end

  defp start_cooldown(%{assigns: %{sounds_cooldown?: true}} = socket, _left_ms), do: socket

  defp start_cooldown(socket, left_ms) do
    Process.send_after(self(), {:soundboard, :cooldown_over}, left_ms)

    assign(socket,
      sounds_cooldown?: true,
      sounds_cooldown_message: Enum.random(@cooldown_messages)
    )
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp sound_path(sound), do: ~p"/sounds/#{sound.file}"

  attr :cooldown?, :boolean, required: true
  attr :cooldown_message, :string, default: nil

  @doc """
  Floating soundboard, a button members drag anywhere on the screen that opens
  the sounds next to it. The Soundboard hook places it, so it stays out of the
  page's layout. Browsers only play audio once the page was clicked, so a hint
  asks for a click when a sound couldn't play
  """
  def soundboard(assigns) do
    assigns = assign(assigns, sounds: Sounds.all())

    ~H"""
    <aside id="soundboard" phx-hook="Soundboard" class="invisible fixed left-0 top-0 z-50">
      <div data-sounds-card class="flex gap-2">
        <button
          type="button"
          data-sounds-toggle
          data-drag-handle
          title="Soundboard"
          aria-controls="soundboard-panel"
          aria-expanded="false"
          class="h-14 w-14 shrink-0 cursor-grab touch-none select-none overflow-hidden rounded-full shadow-lg ring-2 ring-indigo-500 transition hover:ring-indigo-300 active:cursor-grabbing"
        >
          <img
            src={~p"/images/soundboard.jpg"}
            alt="Soundboard"
            draggable="false"
            class="h-full w-full object-cover"
          />
        </button>

        <div
          id="soundboard-panel"
          data-sounds-panel
          hidden
          class="flex max-h-[70dvh] w-80 flex-col rounded-lg border border-gray-700 bg-gray-900/95 shadow-2xl"
        >
          <div
            data-drag-handle
            class="flex cursor-grab touch-none select-none items-center justify-between gap-2 border-b border-gray-700 px-3 py-2 active:cursor-grabbing"
          >
            <h2 class="font-semibold">Soundboard</h2>

            <button
              type="button"
              phx-click="sound:stop"
              class="rounded bg-red-600/80 px-3 py-1 text-sm font-semibold text-white transition hover:bg-red-500"
            >
              ⏹ Stop
            </button>
          </div>

          <div data-sounds-scroll class="min-h-0 flex-1 overflow-y-auto p-3 pb-1">
            <div id="soundboard-volume" phx-update="ignore" class="mb-3">
              <div class="flex items-center gap-2">
                <button
                  type="button"
                  data-sounds-mute
                  title="Mute sounds"
                  class="rounded px-1.5 py-0.5 text-lg hover:bg-white/10"
                >
                  🔊
                </button>
                <input
                  data-sounds-volume
                  type="range"
                  min="0"
                  max="1"
                  step="0.05"
                  value="0.7"
                  aria-label="Sounds volume"
                  class="w-full"
                />
              </div>
              <p data-sounds-blocked hidden class="mt-1 text-sm text-amber-400">
                Click anywhere on the page to hear sounds
              </p>
            </div>

            <p :if={@cooldown?} data-sounds-cooldown class="mb-3 text-sm text-amber-400">
              {@cooldown_message}
            </p>

            <div class="grid grid-cols-2 gap-2">
              <button
                :for={sound <- @sounds}
                type="button"
                phx-click="sound:play"
                phx-value-sound={sound.id}
                data-sound={sound.id}
                title={sound.name}
                disabled={@cooldown?}
                class="truncate rounded-lg bg-gray-700 px-2 py-2 text-left text-sm font-semibold transition hover:bg-gray-600 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {sound.emoji} {sound.name}
              </button>
            </div>

            <p class="mt-3 text-xs text-gray-500">
              Everyone on the server's screen share pages hears the sounds you play.
            </p>
          </div>

          <div
            data-sounds-resize
            title="Drag to resize"
            class="flex h-4 shrink-0 cursor-ns-resize touch-none select-none items-center justify-center"
          >
            <span class="h-1 w-10 rounded-full bg-gray-600"></span>
          </div>
        </div>
      </div>
    </aside>
    """
  end
end
