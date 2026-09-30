defmodule BotchiniWeb.AuthController do
  use BotchiniWeb, :controller

  require Logger

  alias Botchini.Discord.OAuth
  alias BotchiniWeb.Auth

  plug :put_layout, html: {BotchiniWeb.Layouts, :screen}

  @default_return_to "/screens"

  # The screens page is the only one behind the login, and a fixed destination
  # means the login can't be used to send people elsewhere
  def login(conn, _params) do
    render(conn, :login, page_title: "Log in", return_to: @default_return_to, error: nil)
  end

  def discord(conn, _params) do
    if OAuth.configured?() do
      state = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

      conn
      |> put_session(:oauth_state, state)
      |> redirect(external: OAuth.authorize_url(redirect_uri(), state))
    else
      Logger.error("Discord login isn't configured, DISCORD_CLIENT_SECRET is missing")
      login_failed(conn, "Logging in isn't set up on this server yet")
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) when is_binary(state) do
    expected = get_session(conn, :oauth_state)
    conn = delete_session(conn, :oauth_state)

    with true <- is_binary(expected) and Plug.Crypto.secure_compare(expected, state),
         {:ok, user} <- OAuth.fetch_user(code, redirect_uri()) do
      conn
      |> Auth.log_in(user)
      |> redirect(to: ~p"/auth/return")
    else
      false ->
        login_failed(conn, "The login expired, please try again")

      {:error, reason} ->
        Logger.warning("Discord login failed", reason: inspect(reason))
        login_failed(conn, "Discord didn't let us log you in, please try again")
    end
  end

  # Discord sends an error instead of a code when the user cancels
  def callback(conn, _params), do: login_failed(conn, "You need to log in to watch screen shares")

  @doc """
  Where the login ends. The browser script sends the visitor back to the page they came
  from, as the key in its URL fragment never reaches the server
  """
  def return(conn, _params), do: render(conn, :return, page_title: "Logging in")

  defp login_failed(conn, error) do
    conn
    |> put_status(:unauthorized)
    |> render(:login, page_title: "Log in", return_to: @default_return_to, error: error)
  end

  defp redirect_uri, do: url(~p"/auth/discord/callback")
end
