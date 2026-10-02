defmodule BotchiniWeb.ScreenLive.Ads do
  @moduledoc """
  Fake ads shown next to the strip of the guild page, for laughs. Admins choose
  for everyone whether each page picks one when it opens, they change every
  minute, one is always shown, or they're hidden. The guild page calls `mount/2`,
  and passes its `{:ads, message}` and `{:screen_ads, settings}` messages here
  """

  use BotchiniWeb, :html

  import BotchiniWeb.ScreenLive.Components, only: [bar_button: 1, bar_icon: 1, bar_panel_class: 0]

  alias Botchini.Screens
  alias Botchini.Screens.Schema.ScreenSettings

  @ads [
    %{
      id: "dopamine-course",
      name: "Dopamine course",
      image: "/images/ads/dopamine-course.png",
      width: 2000,
      height: 400,
      alt:
        "Dopamine reduction course: feel nothing in just 7 days, only R$ 9,90. " <>
          "Scientists hate this 1 weird trick"
    },
    %{
      id: "riftbound-cards",
      name: "Riftbound cards",
      image: "/images/ads/riftbound-cards.png",
      width: 2000,
      height: 400,
      alt:
        "Banks hate this man: get rich selling Riftbound cards, R$ 5.000/day from your " <>
          "couch. Guaranteed*. Packs opened: 1, cards sold: 3, profit: R$ 0,40"
    },
    %{
      id: "monsterzinho-gelado",
      name: "Monsterzinho gelado",
      image: "/images/ads/monsterzinho-gelado.webp",
      width: 2000,
      height: 667,
      alt:
        "Monsterzinho gelado, gamer edition: several flavors for intense gaming nights, " <>
          "only R$ 9,90 each. \"Fuel of my late nights\", says Mauricio"
    },
    %{
      id: "salve-o-abacate",
      name: "Salve o abacate",
      image: "/images/ads/salve-o-abacate.webp",
      width: 2000,
      height: 667,
      alt:
        "Save the avocado, threatened by modern man. Donate to Mauricio's NGO, " <>
          "Mauricinho Abacatinho: every click is a guacamole of hope"
    },
    %{
      id: "claude-code-morto",
      name: "Claude Code morto",
      image: "/images/ads/claude-code-morto.webp",
      width: 2000,
      height: 667,
      alt:
        "My Claude Code is dead! Mauricio, struggling with merge conflicts and CI, " <>
          "asks if you have what it takes to get his PR up. Click to get in touch"
    }
  ]

  @rotate_every :timer.seconds(60)

  @modes [
    {:random, "🎲 Random", "Each viewer gets one when they open the page"},
    {:rotating, "🔁 Every 60s", "Everyone sees the next one each minute"},
    {:hidden, "🚫 Hidden", "No ads for anyone"}
  ]

  @spec all() :: [map()]
  def all, do: @ads

  @spec get(String.t()) :: map() | nil
  def get(id), do: Enum.find(@ads, &(&1.id == id))

  @doc """
  Shows the ads the guild's admins chose, keeping the page's random pick for
  when they choose random ones
  """
  @spec mount(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def mount(socket, guild_id) do
    socket
    |> assign(ads_random: Enum.random(@ads), ads_timer: nil)
    |> apply_settings(Screens.get_settings(guild_id))
  end

  @doc """
  What an admin chose in the ads menu, if it's one of its choices
  """
  @spec parse_choice(map()) :: {:ok, ScreenSettings.ads_mode(), String.t() | nil} | :error
  def parse_choice(%{"mode" => "fixed", "ad" => ad_id}) do
    if get(ad_id), do: {:ok, :fixed, ad_id}, else: :error
  end

  def parse_choice(%{"mode" => mode}) do
    case Enum.find(@modes, fn {value, _label, _hint} -> Atom.to_string(value) == mode end) do
      {value, _label, _hint} -> {:ok, value, nil}
      nil -> :error
    end
  end

  def parse_choice(_params), do: :error

  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle_info({:screen_ads, %ScreenSettings{} = settings}, socket),
    do: apply_settings(socket, settings)

  def handle_info(:rotate, %{assigns: %{ads_mode: :rotating}} = socket) do
    socket
    |> assign(ad: next(socket.assigns.ad))
    |> schedule_rotation()
  end

  # A rotation that was already on its way when the admins chose something else
  def handle_info(:rotate, socket), do: socket

  defp apply_settings(socket, %ScreenSettings{ads_mode: mode, ad_id: ad_id}) do
    socket = assign(socket, ads_mode: mode, ads_ad_id: ad_id)

    case mode do
      :random -> socket |> cancel_rotation() |> assign(ad: socket.assigns.ads_random)
      :rotating -> socket |> assign(ad: current()) |> schedule_rotation()
      # An ad that's gone since it was chosen leaves the page's random one
      :fixed -> socket |> cancel_rotation() |> assign(ad: get(ad_id) || socket.assigns.ads_random)
      :hidden -> socket |> cancel_rotation() |> assign(ad: nil)
    end
  end

  # Pages count the minutes on the clock, so they all show the same ad and
  # change it at the same time
  defp current do
    minute = div(System.os_time(:millisecond), @rotate_every)
    Enum.at(@ads, rem(minute, length(@ads)))
  end

  defp next(ad) do
    index = Enum.find_index(@ads, &(&1 == ad)) || -1
    Enum.at(@ads, rem(index + 1, length(@ads)))
  end

  defp schedule_rotation(socket) do
    socket = cancel_rotation(socket)
    wait = @rotate_every - rem(System.os_time(:millisecond), @rotate_every)
    assign(socket, ads_timer: Process.send_after(self(), {:ads, :rotate}, wait))
  end

  defp cancel_rotation(%{assigns: %{ads_timer: nil}} = socket), do: socket

  defp cancel_rotation(socket) do
    Process.cancel_timer(socket.assigns.ads_timer)
    assign(socket, ads_timer: nil)
  end

  attr :ad, :map, required: true
  attr :class, :any, default: nil

  def ad(assigns) do
    ~H"""
    <aside id="ad" data-ad={@ad.id} class={["relative w-fit max-w-full", @class]}>
      <img
        src={@ad.image}
        alt={@ad.alt}
        width={@ad.width}
        height={@ad.height}
        class="max-h-30 w-auto max-w-full rounded-lg"
      />
      <span class="pointer-events-none absolute right-1 top-1 rounded bg-black/70 px-1 text-[10px] font-semibold uppercase tracking-wide text-gray-200">
        Ad
      </span>
    </aside>
    """
  end

  attr :mode, :atom, required: true
  attr :ad_id, :string, default: nil

  @doc """
  The admins' button of the bar, which opens the ads' settings above it. It's
  filled while the ads are shown
  """
  def admin_menu(assigns) do
    assigns = assign(assigns, ads: @ads, modes: @modes, bar_panel_class: bar_panel_class())

    ~H"""
    <div id="ads-menu">
      <.bar_button
        id="ads-toggle"
        title="Ads"
        panel="ads-panel"
        aria-pressed={to_string(@mode != :hidden)}
      >
        <.bar_icon name={:megaphone} />
      </.bar_button>

      <div id="ads-panel" data-popover hidden class={@bar_panel_class}>
        <h2 class="border-b border-gray-700 px-3 py-2 text-sm font-semibold">Ads</h2>
        <div class="min-h-0 flex-1 space-y-4 overflow-y-auto p-3 text-sm">
          <div>
            <div class="space-y-1.5">
              <button
                :for={{mode, label, hint} <- @modes}
                type="button"
                phx-click="ads:set"
                phx-value-mode={mode}
                data-ads-mode={mode}
                aria-pressed={to_string(@mode == mode)}
                class="block w-full rounded-lg bg-gray-700 px-3 py-1.5 text-left transition hover:bg-gray-600 aria-pressed:bg-indigo-600"
              >
                <span class="block font-semibold">{label}</span>
                <span class="block text-xs text-gray-300">{hint}</span>
              </button>
            </div>
            <p class="mt-1.5 text-xs text-gray-400">Everyone on the page sees what you choose.</p>
          </div>

          <div>
            <h3 class="mb-1.5 text-xs font-semibold uppercase tracking-wide text-gray-400">
              Always show
            </h3>
            <div class="space-y-1.5">
              <button
                :for={ad <- @ads}
                type="button"
                phx-click="ads:set"
                phx-value-mode="fixed"
                phx-value-ad={ad.id}
                data-ads-pick={ad.id}
                title={ad.name}
                aria-pressed={to_string(@mode == :fixed and @ad_id == ad.id)}
                class="block w-full overflow-hidden rounded-lg ring-indigo-400 transition hover:opacity-90 aria-pressed:ring-2"
              >
                <span class="sr-only">{ad.name}</span>
                <img
                  src={ad.image}
                  alt=""
                  width={ad.width}
                  height={ad.height}
                  loading="lazy"
                  class="w-full"
                />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
