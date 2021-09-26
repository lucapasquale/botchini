defmodule BotchiniDiscord.Twitch do
  @moduledoc """
  Handles Twitch integration with Discord
  """

  @spec format_code(String.t()) :: String.t()
  def format_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end
end
