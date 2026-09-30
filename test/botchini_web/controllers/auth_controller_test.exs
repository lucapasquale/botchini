defmodule BotchiniWebTest.AuthControllerTest do
  use BotchiniWeb.ConnCase, async: true

  use Patch, alias: [patch: :patch_function]

  @moduletag :capture_log

  alias Botchini.Discord.OAuth

  describe "login page" do
    test "links to the Discord login", %{conn: conn} do
      html = conn |> get(~p"/auth/login") |> html_response(200)

      assert html =~ "Log in with Discord"
      assert html =~ ~s(href="/auth/discord?return_to=%2Fscreens")
    end

    test "remembers the guild page to go back to", %{conn: conn} do
      html = conn |> get(~p"/auth/login?return_to=/screens/123") |> html_response(200)

      assert html =~ ~s(href="/auth/discord?return_to=%2Fscreens%2F123")
    end

    test "only goes back to screen pages", %{conn: conn} do
      for path <- ["//evil.com", "https://evil.com", "/screens/../x", "/screens/abc", "/other"] do
        html = conn |> get(~p"/auth/login?#{[return_to: path]}") |> html_response(200)

        assert html =~ ~s(href="/auth/discord?return_to=%2Fscreens")
      end
    end
  end

  describe "discord" do
    test "sends the visitor to Discord asking for their identity only", %{conn: conn} do
      conn = get(conn, ~p"/auth/discord")

      location = redirected_to(conn, 302)
      assert location =~ "https://discord.com/oauth2/authorize?"

      query = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert query["client_id"] == "123"
      assert query["scope"] == "identify"
      assert query["response_type"] == "code"
      assert query["redirect_uri"] =~ "/auth/discord/callback"
      assert query["state"] == get_session(conn, :oauth_state)
    end

    test "remembers where to go back to after the login", %{conn: conn} do
      conn = get(conn, ~p"/auth/discord?return_to=/screens/123")
      assert get_session(conn, :return_to) == "/screens/123"

      conn = get(recycle(conn), ~p"/auth/discord?return_to=https://evil.com")
      assert get_session(conn, :return_to) == "/screens"
    end

    test "fails when the application has no client secret", %{conn: conn} do
      patch_function(OAuth, :configured?, false)

      html = conn |> get(~p"/auth/discord") |> html_response(401)

      assert html =~ "isn&#39;t set up"
    end
  end

  describe "callback" do
    setup %{conn: conn} do
      %{conn: init_test_session(conn, %{oauth_state: "state123"})}
    end

    test "logs the user in", %{conn: conn} do
      patch_function(OAuth, :fetch_user, {:ok, %{id: "10", name: "Ana"}})

      conn = get(conn, ~p"/auth/discord/callback?code=abc&state=state123")

      assert redirected_to(conn) == "/screens"
      assert get_session(conn, "discord_user_id") == "10"
      assert get_session(conn, "discord_user_name") == "Ana"
      assert get_session(conn, :oauth_state) == nil
      assert_called_once(OAuth.fetch_user("abc", _redirect_uri))
    end

    test "goes back to the page the visitor logged in from", %{conn: conn} do
      patch_function(OAuth, :fetch_user, {:ok, %{id: "10", name: "Ana"}})

      conn =
        conn
        |> init_test_session(%{oauth_state: "state123", return_to: "/screens/123"})
        |> get(~p"/auth/discord/callback?code=abc&state=state123")

      assert redirected_to(conn) == "/screens/123"
      assert get_session(conn, :return_to) == nil
    end

    test "rejects a state that isn't the one that was sent", %{conn: conn} do
      patch_function(OAuth, :fetch_user, {:ok, %{id: "10", name: "Ana"}})

      conn = get(conn, ~p"/auth/discord/callback?code=abc&state=other")

      assert html_response(conn, 401) =~ "login expired"
      assert get_session(conn, "discord_user_id") == nil
      refute_called(OAuth.fetch_user(_code, _redirect_uri))
    end

    test "rejects a callback without a login in progress" do
      conn = get(build_conn(), ~p"/auth/discord/callback?code=abc&state=state123")

      assert html_response(conn, 401) =~ "login expired"
    end

    test "fails when Discord doesn't return the user", %{conn: conn} do
      patch_function(OAuth, :fetch_user, {:error, {:status, 400}})

      conn = get(conn, ~p"/auth/discord/callback?code=abc&state=state123")

      assert html_response(conn, 401) =~ "didn&#39;t let us log you in"
      assert get_session(conn, "discord_user_id") == nil
    end

    test "fails when the user cancels", %{conn: conn} do
      conn = get(conn, ~p"/auth/discord/callback?error=access_denied&state=state123")

      assert html_response(conn, 401) =~ "You need to log in"
    end
  end
end
