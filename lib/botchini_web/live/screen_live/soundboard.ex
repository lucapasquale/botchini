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
  and the sounds it plays were played by `actor`
  """
  @spec mount(Phoenix.LiveView.Socket.t(), String.t(), %{id: String.t(), name: String.t()}) ::
          Phoenix.LiveView.Socket.t()
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
      Sounds.play(socket.assigns.sounds_guild_id, sound, socket.assigns.sounds_actor.id)

      Activity.record(
        socket.assigns.sounds_guild_id,
        :sound,
        socket.assigns.sounds_actor.name,
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

    Activity.record(
      socket.assigns.sounds_guild_id,
      :sound_stopped,
      socket.assigns.sounds_actor.name
    )

    socket
  end

  def handle_event(_event, _params, socket), do: socket

  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle_info({:play, sound, user_id}, socket) do
    push_event(socket, "sound:play", %{
      id: sound.id,
      emoji: sound.emoji,
      url: sound_path(sound),
      by: user_id
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

  # Colors members pick for their pointer, which pages send each other by position
  @pointer_colors ~w(#ef4444 #f97316 #facc15 #22c55e #06b6d4 #3b82f6 #8b5cf6 #ec4899 #ffffff #111827)

  @pointer_styles [
    {"matte", "🎨 Matte"},
    {"glossy", "✨ Glossy"},
    {"neon", "💡 Neon"},
    {"sparkle", "🌟 Sparkle"},
    {"rainbow", "🌈 Rainbow"},
    {"pixel", "👾 Pixel"},
    {"comet", "☄️ Comet"}
  ]

  @tab_active "bg-gray-700 text-white"
  @tab_inactive "text-gray-400 hover:text-white"

  attr :cooldown?, :boolean, required: true
  attr :cooldown_message, :string, default: nil

  attr :page_key, :string,
    required: true,
    doc: "Identifies the page, so pointers drawn on it only show on the same page"

  @doc """
  Floating menu, a button members drag anywhere on the screen that opens the
  soundboard and the pointer settings next to it. The Soundboard hook places it,
  so it stays out of the page's layout, and the Pointer hook runs the pointers.
  Browsers only play audio once the page was clicked, so a hint asks for a click
  when a sound couldn't play
  """
  def soundboard(assigns) do
    assigns =
      assign(assigns,
        sounds: Sounds.all(),
        pointer_colors: Enum.with_index(@pointer_colors),
        pointer_styles: @pointer_styles
      )

    ~H"""
    <aside id="soundboard" phx-hook="Soundboard" class="invisible fixed left-0 top-0 z-50">
      <div data-sounds-card class="flex gap-2">
        <button
          type="button"
          data-sounds-toggle
          data-drag-handle
          title="Soundboard and pointer"
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
            <div role="tablist" class="flex gap-1 rounded-lg bg-gray-800 p-1 text-sm font-semibold">
              <button
                id="soundboard-tab-button-sounds"
                type="button"
                role="tab"
                aria-selected="true"
                phx-click={show_tab("sounds", "pointer")}
                class={["rounded-md px-2.5 py-1 transition", tab_class(true)]}
              >
                🔊 Sounds
              </button>
              <button
                id="soundboard-tab-button-pointer"
                type="button"
                role="tab"
                aria-selected="false"
                phx-click={show_tab("pointer", "sounds")}
                class={["rounded-md px-2.5 py-1 transition", tab_class(false)]}
              >
                ✨ Pointer
              </button>
            </div>

            <button
              id="soundboard-stop"
              type="button"
              phx-click="sound:stop"
              class="rounded bg-red-600/80 px-3 py-1 text-sm font-semibold text-white transition hover:bg-red-500"
            >
              ⏹ Stop
            </button>
          </div>

          <div data-sounds-scroll class="min-h-0 flex-1 overflow-y-auto p-3 pb-1">
            <div id="soundboard-tab-sounds" role="tabpanel">
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
              id="soundboard-tab-pointer"
              role="tabpanel"
              phx-hook="Pointer"
              phx-update="ignore"
              data-page-key={@page_key}
              class="hidden space-y-4 text-sm"
            >
              <div>
                <button
                  type="button"
                  data-pointer-toggle
                  aria-pressed="false"
                  class="w-full rounded-lg bg-indigo-600 px-3 py-2 font-semibold text-white transition hover:bg-indigo-500"
                >
                  ✨ Turn my pointer on
                </button>
                <p class="mt-1.5 text-xs text-gray-400">
                  Everyone sees your pointer. Hold the mouse button to draw.
                </p>
              </div>

              <div>
                <h3 class="mb-1.5 text-xs font-semibold uppercase tracking-wide text-gray-400">
                  Color
                </h3>
                <div class="flex flex-wrap gap-2">
                  <button
                    :for={{hex, index} <- @pointer_colors}
                    type="button"
                    data-pointer-color={index}
                    data-hex={hex}
                    title={hex}
                    aria-pressed="false"
                    style={"background-color: #{hex}"}
                    class="h-7 w-7 rounded-full border border-white/20 transition hover:scale-110 aria-pressed:ring-2 aria-pressed:ring-white aria-pressed:ring-offset-2 aria-pressed:ring-offset-gray-900"
                  >
                    <span class="sr-only">{hex}</span>
                  </button>
                </div>
              </div>

              <div>
                <h3 class="mb-1.5 text-xs font-semibold uppercase tracking-wide text-gray-400">
                  Style
                </h3>
                <div class="grid grid-cols-2 gap-1.5">
                  <button
                    :for={{style, label} <- @pointer_styles}
                    type="button"
                    data-pointer-style={style}
                    aria-pressed="false"
                    class="rounded-lg bg-gray-700 px-2 py-1.5 text-left font-semibold transition hover:bg-gray-600 aria-pressed:bg-indigo-600"
                  >
                    {label}
                  </button>
                </div>
              </div>

              <div>
                <h3 class="mb-1.5 flex justify-between text-xs font-semibold uppercase tracking-wide text-gray-400">
                  Width <span data-pointer-width-label></span>
                </h3>
                <input
                  data-pointer-width
                  type="range"
                  min="4"
                  max="24"
                  step="1"
                  value="10"
                  aria-label="Pointer width"
                  class="w-full"
                />
                <canvas
                  data-pointer-preview
                  class="mt-2 h-14 w-full rounded-lg bg-gray-800"
                  aria-hidden="true"
                ></canvas>
              </div>

              <div class="space-y-1.5 border-t border-gray-700 pt-3">
                <button
                  type="button"
                  data-pointer-hide-others
                  aria-pressed="false"
                  class="flex w-full items-center justify-between rounded-lg bg-gray-800 px-3 py-2 text-left transition hover:bg-gray-700"
                >
                  👁️ Hide everyone's pointers <span data-switch>Off</span>
                </button>
                <button
                  type="button"
                  data-pointer-mute-effects
                  aria-pressed="false"
                  class="flex w-full items-center justify-between rounded-lg bg-gray-800 px-3 py-2 text-left transition hover:bg-gray-700"
                >
                  🎆 Mute special effects <span data-switch>Off</span>
                </button>
              </div>
            </div>
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

  defp tab_class(true), do: @tab_active
  defp tab_class(false), do: @tab_inactive

  # Switching tabs stays in the browser, and survives the menu being re-rendered
  defp show_tab(tab, other) do
    JS.show(to: "#soundboard-tab-#{tab}")
    |> JS.hide(to: "#soundboard-tab-#{other}")
    |> JS.add_class(@tab_active, to: "#soundboard-tab-button-#{tab}")
    |> JS.remove_class(@tab_inactive, to: "#soundboard-tab-button-#{tab}")
    |> JS.remove_class(@tab_active, to: "#soundboard-tab-button-#{other}")
    |> JS.add_class(@tab_inactive, to: "#soundboard-tab-button-#{other}")
    |> JS.set_attribute({"aria-selected", "true"}, to: "#soundboard-tab-button-#{tab}")
    |> JS.set_attribute({"aria-selected", "false"}, to: "#soundboard-tab-button-#{other}")
    |> then(
      &if(tab == "sounds",
        do: JS.show(&1, to: "#soundboard-stop"),
        else: JS.hide(&1, to: "#soundboard-stop")
      )
    )
  end
end
