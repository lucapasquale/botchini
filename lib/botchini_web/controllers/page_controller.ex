defmodule BotchiniWeb.PageController do
  use BotchiniWeb, :controller

  alias Botchini.{Discord, Twitch}

  def index(conn, _params) do
    conn
    |> Plug.Conn.assign(:total_servers, Discord.count_guilds())
    |> Plug.Conn.assign(:total_streams, Twitch.count_streams())
    |> Plug.Conn.assign(:add_bot_link, generate_bot_link())
    |> render("index.html")
  end

  defp generate_bot_link() do
    "https://discord.com/api/oauth2/authorize?client_id=#{Application.fetch_env!(:botchini, :discord_app_id)}&permissions=2048&scope=bot%20applications.commands"
  end
end
