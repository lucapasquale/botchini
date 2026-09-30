defmodule BotchiniWeb.ScreenLive.ActivityFeed do
  @moduledoc """
  How what happened on the guild's screen sharing pages is shown, like in the chat
  """

  alias Botchini.Screens.Activity

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
