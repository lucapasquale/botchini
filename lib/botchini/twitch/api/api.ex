defmodule Botchini.Twitch.API do
  @moduledoc """
  Handles communication with Twitch API
  """

  use Tesla

  alias Botchini.Twitch.API.Structs.{Stream, User}

  plug(Tesla.Middleware.JSON)
  plug(Tesla.Middleware.Logger)
  plug(Botchini.Twitch.AuthMiddleware)
  plug(Tesla.Middleware.BaseUrl, "https://api.twitch.tv/helix")

  plug(Tesla.Middleware.Headers, [
    {"Client-ID", Application.fetch_env!(:botchini, :twitch_client_id)}
  ])

  @spec get_user(String.t()) :: User.t() | nil
  def get_user(stream_code) do
    {:ok, %{body: body}} = get("/users", query: [login: stream_code])

    user =
      body
      |> Map.get("data")
      |> List.first()

    if user != nil, do: User.new(user), else: nil
  end

  @spec get_stream(String.t()) :: Stream.t() | nil
  def get_stream(stream_code) do
    {:ok, %{body: body}} = get("/streams", query: [user_login: stream_code])

    stream =
      body
      |> Map.get("data")
      |> List.first()

    if stream != nil, do: Stream.new(stream), else: nil
  end

  @spec add_stream_webhook(String.t()) :: any()
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

  @spec delete_stream_webhook(String.t()) :: any()
  def delete_stream_webhook(subscription_id) do
    delete("/eventsub/subscriptions", query: [id: subscription_id])
  end

  @spec authenticate() :: any()
  def authenticate do
    [Tesla.Middleware.JSON]
    |> Tesla.client()
    |> Tesla.post!("https://id.twitch.tv/oauth2/token", "",
      query: [
        grant_type: "client_credentials",
        client_id: Application.fetch_env!(:botchini, :twitch_client_id),
        client_secret: Application.fetch_env!(:botchini, :twitch_client_secret)
      ]
    )
    |> Map.get(:body)
  end
end
