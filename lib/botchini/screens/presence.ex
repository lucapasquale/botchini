defmodule Botchini.Screens.Presence do
  @moduledoc """
  Tracks the members that have a guild's screen sharing page open. Members are
  keyed by their Discord id, so one with several tabs open is only listed once
  """

  use Phoenix.Presence, otp_app: :botchini, pubsub_server: Botchini.PubSub
end
