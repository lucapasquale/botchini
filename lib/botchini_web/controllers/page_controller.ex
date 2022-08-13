defmodule BotchiniWeb.PageController do
  use BotchiniWeb, :controller

  alias Botchini.{Cache, Creators, Discord}

  @spec index(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def index(conn, _params) do
    {:ok, total_servers} = Cache.get_value("total_servers", &Discord.count_guilds/0)
    {:ok, total_creators} = Cache.get_value("total_creators", &Creators.count_creators/0)

    conn
    |> Plug.Conn.assign(:page_title, "Home")
    |> Plug.Conn.assign(:github_url, "https://github.com/lucapasquale/botchini")
    |> Plug.Conn.assign(:total_servers, total_servers)
    |> Plug.Conn.assign(:total_streams, total_creators)
    |> Plug.Conn.assign(:invite_bot_url, generate_bot_url())
    |> render("index.html")
  end

  defp generate_bot_url do
    "https://discord.com/api/oauth2/authorize?client_id=#{Application.fetch_env!(:botchini, :discord_app_id)}&permissions=2048&scope=bot%20applications.commands"
  end
end
