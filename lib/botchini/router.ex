defmodule Botchini.Router do
  use Plug.Router

  alias Botchini.Twitch.Routes.WebhookCallback

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
  plug(:dispatch)

  get "/status" do
    send_resp(conn, 200, "ok")
  end

  post "/twitch/webhooks/callback" do
    case WebhookCallback.call(conn) do
      {:ok, body} -> send_resp(conn, 200, body)
      {:error, :not_found} -> send_resp(conn, 404, "Invalid")
    end
  end

  match _ do
    send_resp(conn, 404, "Oops!")
  end
end
