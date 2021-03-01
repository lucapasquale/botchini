defmodule Botchini.Twitch.API do
  use Tesla

  plug(Tesla.Middleware.JSON)
  plug(Tesla.Middleware.BaseUrl, Application.fetch_env!(:botchini, :twitch_url))
  plug(Tesla.Middleware.Headers, Application.fetch_env!(:botchini, :twitch_headers))

  def get_user(stream_code) do
    {:ok, %{body: body}} = get("/users", query: [login: stream_code])

    body
    |> Map.get("data")
    |> List.first()
  end

  def add_stream_webhook(user_id) do
    {:ok, %{body: body}} =
      post("/eventsub/subscriptions", %{
        type: "stream.online",
        version: "1",
        condition: %{broadcaster_user_id: user_id},
        transport: %{
          method: "webhook",
          callback: Application.fetch_env!(:botchini, :host) <> "/twitch/webhooks/callback",
          secret: "abcd1234abcd1234abcd1234"
        }
      })

    body
    |> Map.get("data")
    |> List.first()
  end
end
