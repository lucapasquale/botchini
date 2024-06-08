defmodule Botchini.Services.Twitch do
  @moduledoc """
  Handles communication with Twitch API
  """

  require Logger
  alias Botchini.Services.Twitch.AuthMiddleware
  alias Botchini.Services.Twitch.Structs.{Channel, Stream, User}

  @spec search_channels(String.t()) :: list(Channel.t())
  def search_channels(term) do
    resp =
      Req.get!(
        api(),
        url: "/search/channels",
        params: [query: term, first: 10]
      )

    resp.body
    |> Map.get("data")
    |> Enum.map(&Channel.new/1)
  end

  @spec get_user(String.t()) :: {:ok, User.t()} | {:error, nil}
  def get_user(user_id) do
    resp =
      Req.get!(
        api(),
        url: "/users",
        params: [id: user_id]
      )

    user =
      resp.body
      |> Map.get("data")
      |> List.first()

    if user == nil do
      {:error, nil}
    else
      {:ok, User.new(user)}
    end
  end

  @spec get_user_by_user_login(String.t()) :: {:ok, User.t()} | {:error, nil}
  def get_user_by_user_login(user_login) do
    resp =
      Req.get!(
        api(),
        url: "/users",
        params: [login: String.downcase(user_login)]
      )

    user =
      resp.body
      |> Map.get("data")
      |> List.first()

    if user == nil do
      {:error, nil}
    else
      {:ok, User.new(user)}
    end
  end

  @spec get_stream(String.t()) :: {:ok, Stream.t()} | {:error, nil}
  def get_stream(user_id) do
    resp =
      Req.get!(
        api(),
        url: "/streams",
        params: [user_id: user_id]
      )

    stream =
      resp.body
      |> Map.get("data")
      |> List.first()

    if stream == nil do
      {:error, nil}
    else
      {:ok, Stream.new(stream)}
    end
  end

  @spec add_stream_webhook(String.t()) :: any()
  def add_stream_webhook(user_id) do
    resp =
      Req.post!(
        api(),
        url: "/eventsub/subscriptions",
        json: %{
          type: "stream.online",
          version: "1",
          condition: %{broadcaster_user_id: user_id},
          transport: %{
            method: "webhook",
            callback: Application.fetch_env!(:botchini, :host) <> "/api/twitch/webhooks/callback",
            secret: Application.fetch_env!(:botchini, :twitch_webhook_secret)
          }
        }
      )

    resp.body
    |> Map.get("data")
    |> List.first()
  end

  @spec delete_stream_webhook(String.t()) :: any()
  def delete_stream_webhook(subscription_id) do
    Req.delete!(
      api(),
      url: "/eventsub/subscriptions",
      params: [id: subscription_id]
    )
  end

  defp api do
    Req.new(
      base_url: "https://api.twitch.tv/helix",
      auth: {:bearer, AuthMiddleware.get_token()},
      headers: [{"client-id", Application.fetch_env!(:botchini, :twitch_client_id)}]
    )
    |> Req.Request.prepend_response_steps(print_response: &print_response/1)
  end

  defp print_response({request, response}) do
    Logger.info("Request made: #{request.method} #{request.url}")
    Logger.info("Response received: #{response.status}")

    {request, response}
  end
end
