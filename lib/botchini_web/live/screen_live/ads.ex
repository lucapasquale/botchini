defmodule BotchiniWeb.ScreenLive.Ads do
  @moduledoc """
  Fake ads shown next to the strip of the guild page, for laughs. Each page picks
  one when it opens, and admins can hide them for everyone
  """

  use BotchiniWeb, :html

  @ads [
    %{
      id: "dopamine-course",
      image: "/images/ads/dopamine-course.png",
      alt:
        "Dopamine reduction course: feel nothing in just 7 days, only R$ 9,90. " <>
          "Scientists hate this 1 weird trick"
    }
  ]

  @doc """
  One of the ads, at random
  """
  @spec pick() :: map()
  def pick, do: Enum.random(@ads)

  attr :ad, :map, required: true
  attr :class, :any, default: nil

  def ad(assigns) do
    ~H"""
    <aside id="ad" data-ad={@ad.id} class={["relative w-fit max-w-full", @class]}>
      <img
        src={@ad.image}
        alt={@ad.alt}
        width="2000"
        height="400"
        class="max-h-20 w-auto max-w-full rounded-lg"
      />
      <span class="pointer-events-none absolute right-1 top-1 rounded bg-black/70 px-1 text-[10px] font-semibold uppercase tracking-wide text-gray-200">
        Ad
      </span>
    </aside>
    """
  end
end
