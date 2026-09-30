defmodule Botchini.Screens.Presence do
  @moduledoc """
  Tracks the members that have a guild's screen sharing page open. Members are
  keyed by their Discord id, so one with several tabs open is only listed once
  """

  use Phoenix.Presence, otp_app: :botchini, pubsub_server: Botchini.PubSub

  alias Botchini.Screens.Activity

  @topic_prefix "screens:online:"

  @spec topic(String.t()) :: String.t()
  def topic(guild_id), do: @topic_prefix <> guild_id

  @impl true
  def init(_opts), do: {:ok, %{}}

  # Members coming and going are part of the guild's activity
  @impl true
  def handle_metas(@topic_prefix <> guild_id, diff, presences, state) do
    Activity.presence_changed(guild_id, diff, presences)
    {:ok, state}
  end
end
