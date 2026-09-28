defmodule BotchiniWebTest.ScreenLiveTest do
  use BotchiniWeb.ConnCase, async: false

  use Patch, alias: [patch: :patch_function]

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

      html = render(view)
      assert html =~ "post the watch link on Discord"
      assert html =~ ~r"/screens#[^\"<]+"
      refute html =~ ~r"/screens/#{room.id}[\"<]"
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
    defp live_guild(conn, guild_id, signed_at \\ System.system_time(:second)) do
      conn
      |> put_connect_params(%{"key" => Guild.sign_token(guild_id, signed_at)})
      |> live(~p"/screens")
    end

    defp days_ago(days), do: System.system_time(:second) - days * 86_400

    test "requires a valid key", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/screens")
      assert html =~ "Link expired"

      {:ok, _view, html} =
        conn
        |> put_connect_params(%{"key" => "invalid"})
        |> live(~p"/screens")

      assert html =~ "Link expired"
    end

    test "expires after a day when nobody is sharing", %{conn: conn, room: room} do
      Screens.stop_room(room)

      {:ok, _view, html} = live_guild(conn, "1", days_ago(2))
      assert html =~ "Link expired"
    end

    test "keeps working after a day while a room from before it expired is open",
         %{conn: conn, room: room} do
      # The room started after the link expired, so it doesn't keep it working
      {:ok, _view, html} = live_guild(conn, "1", days_ago(2))
      assert html =~ "Link expired"

      started_at = DateTime.add(DateTime.utc_now(), -2, :day)
      patch_function(Screens, :list_rooms, [%{room | live?: true, started_at: started_at}])

      {:ok, _view, html} = live_guild(conn, "1", days_ago(2))
      assert html =~ "Elden Ring"
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

    test "pinned rooms get big and the others shrink below them", %{conn: conn, room: room} do
      other = %{room | id: "other", title: "Hades", started_at: DateTime.utc_now()}
      {:ok, view, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)
      Screens.broadcast(%{other | live?: true}, :live)

      refute has_element?(view, "#screen-#{room.id}.order-2")
      refute has_element?(view, "#screen-other.order-2")

      view |> element("#screen-#{room.id} button[phx-click=pin]") |> render_click()

      refute has_element?(view, "#screen-#{room.id}.order-2")
      assert has_element?(view, "#screen-#{room.id} button[aria-pressed=true]")
      assert has_element?(view, "#screen-other.order-2")

      # Unpinning brings back the grid of equal screens
      view |> element("#screen-#{room.id} button[phx-click=pin]") |> render_click()
      refute has_element?(view, "#screen-other.order-2")
    end

    test "forgets pins of rooms that ended", %{conn: conn, room: room} do
      other = %{room | id: "other", title: "Hades", started_at: DateTime.utc_now()}
      {:ok, view, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)
      Screens.broadcast(%{other | live?: true}, :live)

      view |> element("#screen-other button[phx-click=pin]") |> render_click()
      Screens.broadcast(other, :ended)

      refute has_element?(view, "#screen-#{room.id}.order-2")
      assert has_element?(view, "#screen-#{room.id} button[aria-pressed=false]")
    end

    test "can't pin rooms that aren't on the page", %{conn: conn, room: room} do
      {:ok, view, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)

      render_click(view, "pin", %{"room_id" => "missing"})

      refute has_element?(view, "#screen-#{room.id}.order-2")
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
