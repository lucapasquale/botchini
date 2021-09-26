defmodule BotchiniDiscord.Twitch do
  def format_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end
end
