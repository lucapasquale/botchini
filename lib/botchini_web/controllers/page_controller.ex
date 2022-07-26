defmodule BotchiniWeb.PageController do
  use BotchiniWeb, :controller

  alias Botchini.{Cache, Creators, Discord}

  def index(conn, _params) do
    {:ok, total_servers} = Cache.get_value("total_servers", &Discord.count_guilds/0)
    {:ok, total_creators} = Cache.get_value("total_creators", &Creators.count_creators/0)

    conn
    |> Plug.Conn.assign(:total_servers, total_servers)
    |> Plug.Conn.assign(:total_streams, total_creators)
    |> Plug.Conn.assign(:add_bot_link, generate_bot_link())
    |> render("index.html")
  end

  defp generate_bot_link do
    "https://discord.com/api/oauth2/authorize?client_id=#{Application.fetch_env!(:botchini, :discord_app_id)}&permissions=2048&scope=bot%20applications.commands"
  end
end
