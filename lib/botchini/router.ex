defmodule Botchini.Router do
  use Plug.Router

  use Ecto.Migration
  import Ecto.Query

  alias Botchini.Repo
  alias Botchini.Twitch.Schema.Stream
  alias Botchini.Twitch.Routes.WebhookCallback

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  get "/status" do
    send_resp(conn, 200, "ok")
  end

  get "/custom" do
    all_streams = from(s in Stream) |> Repo.stream()

    Repo.transaction(fn ->
      Enum.to_list(all_streams)
      |> Enum.map(fn stream ->
        user = Botchini.Twitch.API.get_user(stream.code)

        Stream.changeset(stream, %{name: user.display_name})
        |> Repo.update!()
      end)
    end)

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
