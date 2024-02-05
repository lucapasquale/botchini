defmodule BotchiniWeb.StatusController do
  use BotchiniWeb, :controller

  def index(conn, _params) do
    conn |> json(%{ok: true})
  end
end
