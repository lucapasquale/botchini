defmodule Botchini.Router do
  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
  plug(:dispatch)

  post "/twitch/webhooks/callback" do
    # TODO: Verify twitch secret matches

    send_resp(conn, 200, conn.body_params["challenge"])
  end

  match _ do
    send_resp(conn, 404, "Oops!")
  end
end
