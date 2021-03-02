defmodule Botchini.Router do
  use Plug.Router

  alias Botchini.Routes

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
  plug(:dispatch)

  post "/twitch/webhooks/callback" do
    %{status: status, body: body} = Routes.Twitch.webhook_callback(conn)
    send_resp(conn, status, body)
  end

  match _ do
    send_resp(conn, 404, "Oops!")
  end
end
