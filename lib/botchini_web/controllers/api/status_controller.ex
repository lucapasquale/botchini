defmodule BotchiniWeb.Api.StatusController do
  use BotchiniWeb, :controller

  def index(conn, _params) do
    conn |> json(%{ok: true})
  end
end
