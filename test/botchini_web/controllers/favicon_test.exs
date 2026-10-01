defmodule BotchiniWebTest.FaviconTest do
  use BotchiniWeb.ConnCase, async: true

  test "pages link the favicon", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(<link rel="icon" type="image/png" href="/favicon.png")
  end

  test "is served as a PNG and as an icon", %{conn: conn} do
    for {path, type} <- [
          {"/favicon.png", "image/png"},
          {"/favicon.ico", "image/vnd.microsoft.icon"}
        ] do
      conn = get(conn, path)

      assert conn.status == 200
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ type
    end
  end
end
