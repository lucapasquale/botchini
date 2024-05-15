defmodule Botchini.Services.Twitch do
  @moduledoc """
  Handles communication with Twitch API
  """

  # use Tesla

  alias Botchini.Services.Twitch.AuthMiddleware
  alias Botchini.Services.Twitch.Structs.{Channel, Stream, User}

  # plug(Tesla.Middleware.JSON)
  # plug(Tesla.Middleware.Logger)
  # plug(Botchini.Services.Twitch.AuthMiddleware)
  # plug(Tesla.Middleware.BaseUrl, "https://api.twitch.tv/helix")

  # plug(Tesla.Middleware.Headers, [
  #   {"Client-ID", Application.fetch_env!(:botchini, :twitch_client_id)}
  # ])

  @spec search_channels(String.t()) :: list(Channel.t())
  def search_channels(term) do
    resp = api() |> Req.get!(url: "/search/channels", params: [query: term, first: 10])

    resp.body
    |> Map.get("data")
    |> Enum.map(&Channel.new/1)
  end

  @spec get_user(String.t()) :: User.t() | nil
  def get_user(user_id) do
    resp = api() |> Req.get!(url: "/users", params: [id: user_id])

    user =
      resp.body
      |> Map.get("data")
      |> List.first()

    if user != nil, do: User.new(user), else: nil
  end

  @spec get_user_by_user_login(String.t()) :: User.t() | nil
  def get_user_by_user_login(user_login) do
    # {:ok, %{body: body}} = get("/users", query: [login: String.downcase(user_login)])

    # user =
    #   body
    #   |> Map.get("data")
    #   |> List.first()

    # if user != nil, do: User.new(user), else: nil
  end

  @spec get_stream(String.t()) :: Stream.t() | nil
  def get_stream(user_id) do
    # {:ok, %{body: body}} = get("/streams", query: [user_id: user_id])

    # stream =
    #   body
    #   |> Map.get("data")
    #   |> List.first()

    # if stream != nil, do: Stream.new(stream), else: nil
  end

  @spec add_stream_webhook(String.t()) :: any()
  def add_stream_webhook(user_id) do
    # {:ok, %{body: body}} =
    #   post("/eventsub/subscriptions", %{
    #     type: "stream.online",
    #     version: "1",
    #     condition: %{broadcaster_user_id: user_id},
    #     transport: %{
    #       method: "webhook",
    #       callback: Application.fetch_env!(:botchini, :host) <> "/api/twitch/webhooks/callback",
    #       secret: Application.fetch_env!(:botchini, :twitch_webhook_secret)
    #     }
    #   })

    # body
    # |> Map.get("data")
    # |> List.first()
  end

  @spec delete_stream_webhook(String.t()) :: any()
  def delete_stream_webhook(subscription_id) do
    # delete("/eventsub/subscriptions", query: [id: subscription_id])
  end

  defp api() do
    Req.new(
      base_url: "https://api.twitch.tv/helix",
      auth: {:bearer, AuthMiddleware.get_token()},
      headers: [{"client-id", Application.fetch_env!(:botchini, :twitch_client_id)}]
    )
  end
end
