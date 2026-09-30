defmodule BotchiniDiscord.Screens.Responses.Components do
  @moduledoc """
  Generates component messages for screen sharing commands
  """

  use BotchiniWeb, :verified_routes

  alias Nostrum.Constants.{ButtonStyle, ComponentType}

  alias BotchiniWeb.ScreenLive.{Guild, ManageStream}

  @spec share_screen(String.t()) :: map()
  def share_screen(guild_id) do
    %{
      type: ComponentType.action_row(),
      components: [
        link_button("Start sharing", ManageStream.share_url(guild_id)),
        link_button("Watch all", Guild.watch_url(guild_id))
      ]
    }
  end

  @spec watch_all_screens(String.t()) :: map()
  def watch_all_screens(guild_id) do
    %{
      type: ComponentType.action_row(),
      components: [link_button("Watch all", Guild.watch_url(guild_id))]
    }
  end

  @spec whip_url() :: String.t()
  def whip_url, do: url(~p"/api/whip")

  defp link_button(label, url) do
    %{type: ComponentType.button(), style: ButtonStyle.link(), label: label, url: url}
  end
end
