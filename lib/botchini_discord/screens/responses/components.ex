defmodule BotchiniDiscord.Screens.Responses.Components do
  @moduledoc """
  Generates component messages for screen sharing commands
  """

  use BotchiniWeb, :verified_routes

  alias Nostrum.Constants.{ButtonStyle, ComponentType}

  alias Botchini.Screens.Room

  @spec watch_screen(Room.t(), String.t()) :: map()
  def watch_screen(room, label \\ "Watch") do
    %{
      type: ComponentType.action_row(),
      # Discord rejects button labels over 80 characters
      components: [link_button(String.slice(label, 0, 80), watch_url(room))]
    }
  end

  @spec broadcast_screen(Room.t()) :: map()
  def broadcast_screen(room) do
    %{
      type: ComponentType.action_row(),
      components: [
        link_button("Start sharing", broadcast_url(room)),
        link_button("Watch link", watch_url(room))
      ]
    }
  end

  @spec watch_url(Room.t()) :: String.t()
  def watch_url(room), do: url(~p"/screens/#{room.id}")

  # The key goes in the fragment, which browsers never send to the server,
  # so it stays out of request logs, traces and Referer headers
  @spec broadcast_url(Room.t()) :: String.t()
  def broadcast_url(room), do: url(~p"/screens/#{room.id}/broadcast") <> "#" <> room.broadcast_key

  defp link_button(label, url) do
    %{type: ComponentType.button(), style: ButtonStyle.link(), label: label, url: url}
  end
end
