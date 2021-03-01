defmodule Botchini.Router do
  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
  plug(:dispatch)

  post "/twitch/webhooks/callback" do
    # TODO: Verify twitch secret matches
    %{status: status, body: body} = Botchini.Twitch.Callback.handle_callback(conn)

    send_resp(conn, status, body)
  end

  match _ do
    send_resp(conn, 404, "Oops!")
  end
end
