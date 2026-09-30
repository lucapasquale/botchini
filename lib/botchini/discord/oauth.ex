defmodule Botchini.Discord.OAuth do
  @moduledoc """
  Logs users in with their Discord account. Only their identity is asked for, and
  the access token is dropped as soon as it has been used to fetch it
  """

  @authorize_url "https://discord.com/oauth2/authorize"
  @api_url "https://discord.com/api"

  @type user :: %{id: String.t(), name: String.t()}

  @spec configured?() :: boolean()
  def configured?, do: is_binary(client_id()) and is_binary(client_secret())

  @spec authorize_url(String.t(), String.t()) :: String.t()
  def authorize_url(redirect_uri, state) do
    query =
      URI.encode_query(%{
        client_id: client_id(),
        response_type: "code",
        redirect_uri: redirect_uri,
        scope: "identify",
        state: state,
        # Skips the consent screen for users who already allowed it
        prompt: "none"
      })

    @authorize_url <> "?" <> query
  end

  @doc """
  Trades the code Discord sent back for the user who logged in
  """
  @spec fetch_user(String.t(), String.t()) :: {:ok, user()} | {:error, term()}
  def fetch_user(code, redirect_uri) do
    with {:ok, token} <- exchange_code(code, redirect_uri),
         {:ok, %{"id" => id} = user} <- get("/users/@me", auth: {:bearer, token}) do
      {:ok, %{id: id, name: user["global_name"] || user["username"] || id}}
    end
  end

  defp exchange_code(code, redirect_uri) do
    form = [
      client_id: client_id(),
      client_secret: client_secret(),
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri
    ]

    with {:ok, %{"access_token" => token}} <- post("/oauth2/token", form), do: {:ok, token}
  end

  defp post(path, form), do: request(:post, path, form: form)
  defp get(path, opts), do: request(:get, path, opts)

  defp request(method, path, opts) do
    case Req.request([method: method, url: @api_url <> path, retry: false] ++ opts) do
      {:ok, %Req.Response{status: 200, body: %{} = body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:status, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp client_id, do: Application.get_env(:botchini, :discord_app_id)
  defp client_secret, do: Application.get_env(:botchini, :discord_client_secret)
end
