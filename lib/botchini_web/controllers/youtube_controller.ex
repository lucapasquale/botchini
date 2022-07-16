defmodule BotchiniWeb.YoutubeController do
  use BotchiniWeb, :controller

  require Logger

  @spec callback(Plug.Conn.t(), any) :: Plug.Conn.t()
  def callback(conn, _params) do
    challenge = conn.params["hub.challenge"]

    text(conn, challenge)
  end
end
