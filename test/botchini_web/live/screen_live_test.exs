defmodule BotchiniWebTest.ScreenLiveTest do
  use BotchiniWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Botchini.Screens
  alias BotchiniWeb.ScreenLive.Guild

  setup do
    {:ok, room} =
      Screens.start_room(%{
        title: "Elden Ring",
        guild_id: "1",
        channel_id: "2",
        owner_id: "3",
        owner_name: "Luca"
      })

    on_exit(fn -> Screens.stop_room(room) end)

    %{room: room}
  end

  describe "watch page" do
    test "shows the room waiting for the broadcaster", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/screens/#{room.id}")

      assert html =~ "Elden Ring"
      assert html =~ "Waiting for Luca to start sharing"
      refute html =~ room.broadcast_key
    end

    test "shows when the room ends", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")

      Screens.stop_room(room)

      assert render(view) =~ "Screen share ended"
    end

    test "shows unknown rooms as not found", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/screens/unknown")

      assert html =~ "Screen share not found"
    end

    test "replies with an error to invalid offers", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")

      render_hook(view, "offer", %{"type" => "offer"})

      assert_reply(view, %{error: "Couldn't connect to the screen share"})
    end
  end

  describe "broadcast page" do
    test "requires the broadcast key", %{conn: conn, room: room} do
      {:ok, _view, html} =
        conn
        |> put_connect_params(%{"key" => room.id})
        |> live(~p"/screens/#{room.id}/broadcast")

      assert html =~ "Screen share not found"

      {:ok, _view, html} = live(conn, ~p"/screens/#{room.id}/broadcast")
      assert html =~ "Screen share not found"
    end

    test "lets the owner share and stop their screen", %{conn: conn, room: room} do
      {:ok, view, html} =
        conn
        |> put_connect_params(%{"key" => room.broadcast_key})
        |> live(~p"/screens/#{room.id}/broadcast")

      assert html =~ "Share screen"

      render_hook(view, "stop", %{})

      assert render(view) =~ "Screen share ended"
      assert Screens.get_room(room.id) == nil
    end

    test "shows the watch link when it couldn't be posted on Discord", %{conn: conn, room: room} do
      {:ok, view, html} =
        conn
        |> put_connect_params(%{"key" => room.broadcast_key})
        |> live(~p"/screens/#{room.id}/broadcast")

      refute html =~ "post the watch link on Discord"

      Screens.broadcast_announcement_failed(room)

      assert render(view) =~ "post the watch link on Discord"
      assert render(view) =~ "/screens/#{room.id}"
    end

    test "names the room after the shared source or the owner's title", %{conn: conn, room: room} do
      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"key" => room.broadcast_key})
        |> live(~p"/screens/#{room.id}/broadcast")

      render_hook(view, "source", %{"surface" => "window"})
      assert render(view) =~ "Luca&#39;s window"

      view |> form("#screen-title", title: "Speedrun") |> render_submit()
      assert render(view) =~ "Speedrun"
      assert Screens.get_room(room.id).title == "Speedrun"
    end

    test "doesn't check the key before connecting", %{conn: conn, room: room} do
      html = conn |> get(~p"/screens/#{room.id}/broadcast") |> html_response(200)

      assert html =~ "Connecting..."
      refute html =~ "Elden Ring"
    end
  end

  describe "guild page" do
    defp live_guild(conn, guild_id) do
      conn
      |> put_connect_params(%{"key" => Guild.sign_token(guild_id)})
      |> live(~p"/screens")
    end

    test "requires a valid key", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/screens")
      assert html =~ "Link expired"

      {:ok, _view, html} =
        conn
        |> put_connect_params(%{"key" => "invalid"})
        |> live(~p"/screens")

      assert html =~ "Link expired"
    end

    test "shows the guild's rooms while they're live", %{conn: conn, room: room} do
      {:ok, view, html} = live_guild(conn, "1")
      assert html =~ "Nobody is sharing their screen right now"

      Screens.broadcast(%{room | live?: true}, :live)
      assert render(view) =~ "Elden Ring"
      assert has_element?(view, "#screen-viewer-#{room.id}")

      Screens.broadcast(%{room | live?: false}, :updated)
      assert render(view) =~ "Waiting for Luca to start sharing"

      Screens.broadcast(room, :ended)
      refute render(view) =~ "Elden Ring"
    end

    test "doesn't show other guilds' rooms", %{conn: conn, room: room} do
      {:ok, view, _html} = live_guild(conn, "9")

      Screens.broadcast(%{room | live?: true}, :live)

      refute render(view) =~ "Elden Ring"
    end

    test "only connects to rooms on the page", %{conn: conn, room: room} do
      {:ok, view, _html} = live_guild(conn, "1")

      render_hook(view, "offer", %{"room_id" => room.id, "type" => "offer", "sdp" => ""})

      assert_reply(view, %{error: "Couldn't connect to the screen share"})
    end
  end
end
