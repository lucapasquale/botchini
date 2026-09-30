defmodule BotchiniWebTest.ScreenLiveTest do
  use BotchiniWeb.ConnCase, async: false

  use Patch, alias: [patch: :patch_function]

  @moduletag :capture_log

  alias Botchini.Discord
  alias Botchini.Screens
  alias BotchiniWeb.ScreenLive.Guild

  setup %{conn: conn} do
    {:ok, room} =
      Screens.start_room(%{
        title: "Elden Ring",
        guild_id: "1",
        channel_id: "2",
        owner_id: "3",
        owner_name: "Luca"
      })

    on_exit(fn -> Screens.stop_room(room) end)

    patch_function(Discord, :check_member, :member)

    %{room: room, conn: log_in(conn)}
  end

  defp log_in(conn),
    do: init_test_session(conn, %{"discord_user_id" => "10", "discord_user_name" => "Ana"})

  describe "login" do
    test "is needed to watch a room", %{room: room} do
      assert {:error, {:redirect, %{to: to}}} = live(build_conn(), ~p"/screens/#{room.id}")
      assert to == "/auth/login?return_to=%2Fscreens%2F#{room.id}"
    end

    test "is needed for the guild page" do
      conn = get(build_conn(), ~p"/screens")

      assert redirected_to(conn) == "/auth/login?return_to=%2Fscreens"
    end

    test "isn't needed to broadcast", %{room: room} do
      {:ok, _view, html} =
        build_conn()
        |> put_connect_params(%{"key" => room.broadcast_key})
        |> live(~p"/screens/#{room.id}/broadcast")

      assert html =~ "Share screen"
    end

    test "shows who is logged in", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/screens/#{room.id}")

      assert html =~ "Ana"
    end
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

  describe "online members on the watch page" do
    test "lists who has the server's pages open", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")
      assert has_element?(view, "#online-10", "Ana")
      assert has_element?(view, "#online-10", "(you)")

      {:ok, guild_page, _html} = conn |> log_in_as("11", "Bia") |> live_guild("1")

      # The pages share one list
      eventually(fn ->
        assert has_element?(view, "#online-list", "Online · 2")
        assert has_element?(view, "#online-11", "Bia")
        assert has_element?(guild_page, "#online-10", "Ana")
      end)

      GenServer.stop(guild_page.pid)

      eventually(fn -> refute has_element?(view, "#online-11") end)
    end

    test "shows admins in their own color", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")

      patch_function(Discord, :check_member, :admin)
      {:ok, _admin, _html} = conn |> log_in_as("11", "Bia") |> live(~p"/screens/#{room.id}")

      eventually(fn -> assert has_element?(view, "#online-11.text-amber-300", "Bia") end)
      refute has_element?(view, "#online-10.text-amber-300")
    end

    test "is still shown when the room ends", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")

      Screens.stop_room(room)

      assert render(view) =~ "Screen share ended"
      assert has_element?(view, "#online-10", "Ana")
    end

    test "leaves out other guilds and people that got denied", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")
      {:ok, _other_guild, _html} = conn |> log_in_as("11", "Bia") |> live_guild("9")

      patch_function(Discord, :check_member, :not_member)
      {:ok, _denied, _html} = conn |> log_in_as("12", "Caio") |> live(~p"/screens/#{room.id}")

      Process.sleep(50)

      assert render(view) =~ "Online · 1"
      refute has_element?(view, "#online-11")
      refute has_element?(view, "#online-12")
    end
  end

  describe "server membership" do
    test "lets members watch a room", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/screens/#{room.id}")

      assert html =~ "Elden Ring"
      assert_called(Discord.check_member("1", "10"))
    end

    test "keeps other people out of a room", %{conn: conn, room: room} do
      patch_function(Discord, :check_member, :not_member)

      {:ok, view, html} = live(conn, ~p"/screens/#{room.id}")

      assert html =~ "Not in this server"
      refute html =~ "Elden Ring"
      refute render(view) =~ "Elden Ring"
    end

    test "keeps other people out of the guild page", %{conn: conn, room: room} do
      patch_function(Discord, :check_member, :not_member)

      {:ok, view, _html} = live_guild(conn, room.guild_id)

      assert render(view) =~ "Not in this server"
      refute render(view) =~ "Elden Ring"
      assert_called(Discord.check_member("1", "10"))
    end

    test "asks to try again when Discord can't tell", %{conn: conn, room: room} do
      patch_function(Discord, :check_member, :error)

      {:ok, _view, html} = live(conn, ~p"/screens/#{room.id}")
      assert html =~ "check your access"

      {:ok, view, _html} = live_guild(conn, room.guild_id)
      assert render(view) =~ "check your access"
    end

    test "doesn't ask Discord for links that don't work", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/screens/unknown")
      assert html =~ "Screen share not found"

      {:ok, _view, html} = live(conn, ~p"/screens")
      assert html =~ "Link expired"

      refute_called(Discord.check_member(_guild_id, _user_id))
    end
  end

  describe "closing a screen share" do
    defp live_guild_with_room(conn, room) do
      {:ok, view, _html} = live_guild(conn, room.guild_id)
      Screens.broadcast(%{room | live?: true}, :live)
      render(view)

      view
    end

    test "is offered to admins on both pages", %{conn: conn, room: room} do
      patch_function(Discord, :check_member, :admin)

      {:ok, _view, html} = live(conn, ~p"/screens/#{room.id}")
      assert html =~ ~s(phx-click="close")

      view = live_guild_with_room(conn, room)
      assert has_element?(view, ~s(button[phx-click="close"]))
    end

    test "isn't offered to other members", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/screens/#{room.id}")
      refute html =~ ~s(phx-click="close")

      view = live_guild_with_room(conn, room)
      refute has_element?(view, ~s(button[phx-click="close"]))
    end

    test "ends the room from its page", %{conn: conn, room: room} do
      patch_function(Discord, :check_member, :admin)
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")

      view |> element(~s(button[phx-click="close"])) |> render_click()

      assert render(view) =~ "Screen share ended"
      assert Screens.get_room(room.id) == nil
    end

    test "ends the room from the guild page", %{conn: conn, room: room} do
      patch_function(Discord, :check_member, :admin)
      view = live_guild_with_room(conn, room)

      view |> element(~s(button[phx-click="close"])) |> render_click()

      refute has_element?(view, "#screen-#{room.id}")
      assert Screens.get_room(room.id) == nil
    end

    test "checks the user is still an admin when closing", %{conn: conn, room: room} do
      patch_function(Discord, :check_member, :admin)
      {:ok, page, _html} = live(conn, ~p"/screens/#{room.id}")
      guild_page = live_guild_with_room(conn, room)

      patch_function(Discord, :check_member, :member)

      render_hook(page, "close", %{})
      render_hook(guild_page, "close", %{"room_id" => room.id})

      assert %{live?: _live} = Screens.get_room(room.id)
      refute has_element?(guild_page, ~s(button[phx-click="close"]))
    end

    test "can't be forged by members", %{conn: conn, room: room} do
      {:ok, page, _html} = live(conn, ~p"/screens/#{room.id}")
      guild_page = live_guild_with_room(conn, room)

      render_hook(page, "close", %{})
      render_hook(guild_page, "close", %{"room_id" => room.id})

      assert Screens.get_room(room.id)
    end

    test "only closes rooms on the guild page", %{conn: conn, room: room} do
      {:ok, other} =
        Screens.start_room(%{
          title: "Other server",
          guild_id: "9",
          channel_id: "2",
          owner_id: "4",
          owner_name: "Bia"
        })

      on_exit(fn -> Screens.stop_room(other) end)

      patch_function(Discord, :check_member, :admin)
      view = live_guild_with_room(conn, room)

      render_hook(view, "close", %{"room_id" => other.id})
      render_hook(view, "close", %{"room_id" => "unknown"})

      assert Screens.get_room(other.id)
      assert Screens.get_room(room.id)
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

    test "tells the broadcaster's browser when viewers join and leave", %{conn: conn, room: room} do
      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"key" => room.broadcast_key})
        |> live(~p"/screens/#{room.id}/broadcast")

      Screens.broadcast(%{room | viewer_count: 1}, :updated)
      assert_push_event(view, "screen:viewer_joined", %{})

      Screens.broadcast(%{room | viewer_count: 3}, :updated)
      assert_push_event(view, "screen:viewer_joined", %{})

      Screens.broadcast(%{room | viewer_count: 2}, :updated)
      assert_push_event(view, "screen:viewer_left", %{})

      Screens.broadcast(%{room | viewer_count: 0}, :updated)
      assert_push_event(view, "screen:viewer_left", %{})
    end

    test "stays quiet when the viewers didn't change", %{conn: conn, room: room} do
      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"key" => room.broadcast_key})
        |> live(~p"/screens/#{room.id}/broadcast")

      Screens.broadcast(%{room | viewer_count: 1}, :updated)
      assert_push_event(view, "screen:viewer_joined", %{})

      Screens.broadcast(%{room | viewer_count: 1, title: "Speedrun"}, :updated)
      assert render(view) =~ "Speedrun"

      refute_push_event(view, "screen:viewer_joined", %{}, 50)
      refute_push_event(view, "screen:viewer_left", %{}, 50)
    end

    test "doesn't count everyone leaving as viewers leaving when the room ends",
         %{conn: conn, room: room} do
      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"key" => room.broadcast_key})
        |> live(~p"/screens/#{room.id}/broadcast")

      Screens.broadcast(%{room | viewer_count: 2}, :updated)
      assert_push_event(view, "screen:viewer_joined", %{})

      Screens.broadcast(%{room | viewer_count: 0}, :ended)

      assert render(view) =~ "Screen share ended"
      refute_push_event(view, "screen:viewer_left", %{}, 50)
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

    defp log_in_as(conn, id, name),
      do: init_test_session(conn, %{"discord_user_id" => id, "discord_user_name" => name})

    # Presence changes reach the page as messages, so they're not there right away
    defp eventually(fun, attempts \\ 20) do
      fun.()
    rescue
      error in ExUnit.AssertionError ->
        if attempts == 0 do
          reraise error, __STACKTRACE__
        else
          Process.sleep(25)
          eventually(fun, attempts - 1)
        end
    end

    test "lists who is online, as they come and go", %{conn: conn} do
      {:ok, view, html} = live_guild(conn, "1")
      assert html =~ "Online · 1"
      assert has_element?(view, "#online-10", "Ana")
      assert has_element?(view, "#online-10", "(you)")

      {:ok, other, _html} = conn |> log_in_as("11", "Bia") |> live_guild("1")

      eventually(fn ->
        assert has_element?(view, "#online-list", "Online · 2")
        assert has_element?(view, "#online-11", "Bia")
        refute has_element?(view, "#online-11", "(you)")
      end)

      GenServer.stop(other.pid)

      eventually(fn ->
        assert has_element?(view, "#online-list", "Online · 1")
        refute has_element?(view, "#online-11")
      end)
    end

    test "lists members with several tabs open once", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, tab, _html} = live_guild(conn, "1")

      eventually(fn -> assert has_element?(view, "#online-list", "Online · 1") end)

      # They're still online while one tab is left
      GenServer.stop(tab.pid)
      Process.sleep(50)
      render(view)

      assert has_element?(view, "#online-list", "Online · 1")
      assert has_element?(view, "#online-10")
    end

    test "is shown while nobody is sharing", %{conn: conn} do
      {:ok, view, html} = live_guild(conn, "1")

      assert html =~ "Nobody is sharing their screen right now"
      assert has_element?(view, "#online-10", "Ana")
    end

    test "is shown next to the screens", %{conn: conn, room: room} do
      view = live_guild_with_room(conn, room)

      assert has_element?(view, "#screen-#{room.id}")
      assert has_element?(view, "#online-10", "Ana")
    end

    test "only has the guild's members that got in", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")

      {:ok, _other_guild, _html} = conn |> log_in_as("11", "Bia") |> live_guild("9")

      patch_function(Discord, :check_member, :not_member)
      {:ok, _denied, _html} = conn |> log_in_as("12", "Caio") |> live_guild("1")

      # Once the others had time to show up, if they were going to
      Process.sleep(50)
      html = render(view)

      assert html =~ "Online · 1"
      refute html =~ "Bia"
      refute html =~ "Caio"
    end

    test "shows admins in their own color", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      refute has_element?(view, "#online-10.text-amber-300")

      patch_function(Discord, :check_member, :admin)
      {:ok, _admin, _html} = conn |> log_in_as("11", "Bia") |> live_guild("1")

      eventually(fn ->
        assert has_element?(view, "#online-11.text-amber-300", "Bia")
        assert has_element?(view, "#online-11", "(admin)")
      end)

      # Members keep the usual color
      refute has_element?(view, "#online-10.text-amber-300")
      refute has_element?(view, "#online-10", "(admin)")
    end

    test "shows a member as admin while any of their tabs is one", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      patch_function(Discord, :check_member, :admin)
      {:ok, _tab, _html} = live_guild(conn, "1")

      eventually(fn -> assert has_element?(view, "#online-10.text-amber-300") end)
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

  describe "soundboard" do
    defp play(view, sound_id),
      do: view |> element("#soundboard button[phx-value-sound=#{sound_id}]") |> render_click()

    test "plays sounds for everyone on the guild's pages", %{conn: conn, room: room} do
      {:ok, watch, _html} = live(conn, ~p"/screens/#{room.id}")
      {:ok, guild, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)

      play(watch, "volibero")

      assert_push_event(watch, "sound:play", %{
        id: "volibero",
        emoji: "🐻",
        url: "/sounds/volibero.mp3"
      })

      assert_push_event(guild, "sound:play", %{id: "volibero"})
    end

    test "works while nobody is sharing", %{conn: conn, room: room} do
      Screens.stop_room(room)
      {:ok, guild, html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(conn, "1")

      assert html =~ "Nobody is sharing their screen right now"
      play(guild, "mj")

      assert_push_event(other, "sound:play", %{id: "mj"})
    end

    test "stops the sound for everyone", %{conn: conn, room: room} do
      {:ok, watch, _html} = live(conn, ~p"/screens/#{room.id}")
      {:ok, guild, _html} = live_guild(conn, "1")

      watch |> element("#soundboard button[phx-click='sound:stop']") |> render_click()

      assert_push_event(watch, "sound:stop", %{})
      assert_push_event(guild, "sound:stop", %{})
    end

    test "doesn't play sounds for other guilds", %{conn: conn, room: room} do
      {:ok, watch, _html} = live(conn, ~p"/screens/#{room.id}")
      {:ok, other, _html} = live_guild(conn, "9")

      play(watch, "volibero")

      assert_push_event(watch, "sound:play", %{id: "volibero"})
      refute_push_event(other, "sound:play", %{})
    end

    test "waits after three sounds in a row", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")

      for _ <- 1..3, do: play(view, "scooby-doo")

      assert has_element?(view, "#soundboard [data-sounds-cooldown]")
      assert has_element?(view, "#soundboard button[phx-value-sound=scooby-doo][disabled]")

      # Clicks during the cooldown, e.g. from a stale page, don't play
      render_click(view, "sound:play", %{"sound" => "scooby-doo"})
      for _ <- 1..3, do: assert_push_event(view, "sound:play", %{id: "scooby-doo"})
      refute_push_event(view, "sound:play", %{})
    end

    test "ignores unknown sounds", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")

      render_click(view, "sound:play", %{"sound" => "missing"})

      refute_push_event(view, "sound:play", %{})
    end
  end
end
