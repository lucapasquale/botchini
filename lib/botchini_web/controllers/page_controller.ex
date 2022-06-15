defmodule BotchiniWeb.PageController do
  use BotchiniWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
