defmodule BotchiniWeb.PageController do
  use BotchiniWeb, :controller

  alias Botchini.{Cache, Creators, Discord}

  def home(conn, _params) do
    {:ok, total_servers} = Cache.get_or_set("total_servers", &Discord.count_guilds/0)
    {:ok, total_creators} = Cache.get_or_set("total_creators", &Creators.count_creators/0)

    conn
    |> Plug.Conn.assign(:page_title, "Botchini")
    |> Plug.Conn.assign(:invite_bot_url, generate_bot_url())
    |> Plug.Conn.assign(:github_url, "https://github.com/lucapasquale/botchini")
    |> Plug.Conn.assign(:total_servers, total_servers)
    |> Plug.Conn.assign(:total_streams, total_creators)
    |> render(:home)
  end

  defp generate_bot_url do
    app_id = Application.fetch_env!(:botchini, :discord_app_id)

    "https://discord.com/api/oauth2/authorize?client_id=#{app_id}&permissions=2048&scope=bot%20applications.commands"
  end
end
