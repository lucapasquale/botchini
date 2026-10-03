defmodule BotchiniWebTest.ScreenLiveTest do
  use BotchiniWeb.ConnCase, async: false

  use Patch, alias: [patch: :patch_function]

  @moduletag :capture_log

  alias Botchini.Discord
  alias Botchini.Music.YtDlp
  alias Botchini.Screens
  alias Botchini.Screens.{Activity, Jukebox}
  alias BotchiniWeb.ScreenLive.{Ads, Guild}

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

    Activity.clear("1")
    patch_function(Discord, :check_member, :member)

    %{room: room, conn: log_in(conn)}
  end

  defp log_in(conn),
    do: init_test_session(conn, %{"discord_user_id" => "10", "discord_user_name" => "Ana"})

  describe "login" do
    test "is needed for the guild page, and brings the visitor back to it" do
      conn = get(build_conn(), ~p"/screens/1")

      assert redirected_to(conn) == "/auth/login?return_to=%2Fscreens%2F1"
    end

    test "shows who is logged in", %{conn: conn} do
      {:ok, _view, html} = live_guild(conn, "1")

      assert html =~ "Ana"
    end
  end

  describe "single screen page" do
    test "is gone, as everyone watches on the guild page", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/screens/#{room.id}")

      assert render(view) =~ "Server not found"
      refute render(view) =~ "Elden Ring"
    end

    test "isn't linked from the guild page", %{conn: conn, room: room} do
      view = live_guild_with_room(conn, room)

      refute has_element?(view, ~s(a[href="/screens/#{room.id}"]))
    end
  end

  describe "activity" do
    # Pages closed by earlier tests leave the guild's activity shortly after, and a
    # member coming back right away doesn't count as joining. So each test has members
    # nobody else uses, and only looks at what they did
    setup %{conn: conn} do
      n = System.unique_integer([:positive])

      %{conn: log_in_as(conn, "me-#{n}", "Ana#{n}"), me: "Ana#{n}", n: n}
    end

    defp log_in_other(conn, n, label),
      do: log_in_as(conn, "#{label}-#{n}", "#{label}#{n}")

    test "shows what happened before the page opened, newest first", %{conn: conn, n: n} do
      Activity.record("1", :stream_started, "Luca#{n}")
      Activity.record("1", :sound, "Bia#{n}", "🐻 Volibero")
      Activity.record("9", :sound, "Caio#{n}", "🐻 Volibero")

      {:ok, view, _html} = live_guild(conn, "1")

      assert has_element?(view, "#chat-lines", "Luca#{n} started streaming")
      assert has_element?(view, "#chat-lines", "Bia#{n} played 🐻 Volibero")
      refute has_element?(view, "#chat-lines", "Caio#{n}")

      # Like a chat, the latest line is at the bottom
      html = render(view)

      assert :binary.match(html, "Luca#{n} started") < :binary.match(html, "Bia#{n} played")
    end

    test "gets new events as they happen", %{conn: conn, n: n} do
      {:ok, view, _html} = live_guild(conn, "1")

      Activity.record("1", :stream_ended, "Luca#{n}", "closed by an admin")

      eventually(fn ->
        assert has_element?(
                 view,
                 "#chat-lines",
                 "Luca#{n} stopped streaming (closed by an admin)"
               )
      end)
    end

    test "shows who joined", %{conn: conn, n: n} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, _other, _html} = conn |> log_in_other(n, "Bia") |> live_guild("1")

      eventually(fn -> assert has_element?(view, "#chat-lines", "Bia#{n} joined") end)
    end

    test "doesn't show more tabs of someone who is online as joining", %{conn: conn, n: n} do
      {:ok, view, _html} = live_guild(conn, "1")
      bia = log_in_other(conn, n, "Bia")
      {:ok, _tab, _html} = live_guild(bia, "1")
      eventually(fn -> assert has_element?(view, "#chat-lines", "Bia#{n} joined") end)

      {:ok, _other_tab, _html} = live_guild(bia, "1")
      Process.sleep(100)

      # Rendering an element that matches more than once raises
      assert view |> element("#chat-lines li", "Bia#{n} joined") |> render() =~
               "Bia#{n} joined"
    end

    test "shows who left, but not who just reloaded the page", %{conn: conn, n: n} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, bia, _html} = conn |> log_in_other(n, "Bia") |> live_guild("1")
      eventually(fn -> assert has_element?(view, "#chat-lines", "Bia#{n} joined") end)

      # Reloading closes the page and opens it again right away
      GenServer.stop(bia.pid)
      {:ok, _bia_again, _html} = conn |> log_in_other(n, "Bia") |> live_guild("1")
      Process.sleep(300)
      refute has_element?(view, "#chat-lines", "Bia#{n} left")

      {:ok, caio, _html} = conn |> log_in_other(n, "Caio") |> live_guild("1")
      eventually(fn -> assert has_element?(view, "#chat-lines", "Caio#{n} joined") end)

      GenServer.stop(caio.pid)
      eventually(fn -> assert has_element?(view, "#chat-lines", "Caio#{n} left") end)
    end

    test "shows the sounds members play and stop", %{conn: conn, n: n} do
      {:ok, watcher, _html} = live_guild(conn, "1")
      {:ok, player, _html} = conn |> log_in_other(n, "Bia") |> live_guild("1")

      render_hook(player, "sound:play", %{"sound" => "volibero"})

      eventually(fn ->
        assert has_element?(watcher, "#chat-lines", "Bia#{n} played 🐻 Volibero")
      end)

      render_hook(player, "sound:stop", %{})

      eventually(fn ->
        assert has_element?(watcher, "#chat-lines", "Bia#{n} stopped the sounds")
      end)
    end

    test "leaves out sounds that don't exist", %{conn: conn, n: n} do
      {:ok, view, _html} = live_guild(conn, "1")

      render_hook(view, "sound:play", %{"sound" => "unknown"})
      Process.sleep(50)

      refute has_element?(view, "#chat-lines", "Ana#{n} played")
    end
  end

  describe "server membership" do
    test "lets members watch the guild's rooms", %{conn: conn, room: room} do
      view = live_guild_with_room(conn, room)

      assert render(view) =~ "Elden Ring"
      assert_called(Discord.check_member("1", "10"))
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

      {:ok, view, _html} = live_guild(conn, room.guild_id)
      assert render(view) =~ "check your access"
    end

    test "doesn't ask Discord for links that don't work", %{conn: conn} do
      for path <- [
            ~p"/screens",
            ~p"/screens/abc",
            ~p"/screens/1x",
            "/screens/#{String.duplicate("1", 21)}"
          ] do
        {:ok, view, _html} = live(conn, path)
        assert render(view) =~ "Server not found"
      end

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

    test "is offered to admins", %{conn: conn, room: room} do
      patch_function(Discord, :check_member, :admin)

      view = live_guild_with_room(conn, room)
      assert has_element?(view, ~s(button[phx-click="close"]))
    end

    test "isn't offered to other members", %{conn: conn, room: room} do
      view = live_guild_with_room(conn, room)
      refute has_element?(view, ~s(button[phx-click="close"]))
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
      guild_page = live_guild_with_room(conn, room)

      patch_function(Discord, :check_member, :member)

      render_hook(guild_page, "close", %{"room_id" => room.id})

      assert %{live?: _live} = Screens.get_room(room.id)
      refute has_element?(guild_page, ~s(button[phx-click="close"]))
    end

    test "can't be forged by members", %{conn: conn, room: room} do
      guild_page = live_guild_with_room(conn, room)

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

  describe "guild page" do
    defp live_guild(conn, guild_id), do: live(conn, ~p"/screens/#{guild_id}")

    test "has a fixed link for each guild" do
      assert Guild.watch_url("1") =~ ~r"^https?://[^/]+/screens/1$"
    end

    test "only asks Discord once connected", %{conn: conn} do
      html = conn |> get(~p"/screens/1") |> html_response(200)

      assert html =~ "Connecting..."
      refute_called(Discord.check_member(_guild_id, _user_id))
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

    test "watches the first screen big, and another one when clicked", %{conn: conn, room: room} do
      other = %{
        room
        | id: "other",
          title: "Hades",
          owner_name: "Bia",
          started_at: DateTime.utc_now()
      }

      {:ok, view, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)
      Screens.broadcast(%{other | live?: true}, :live)

      assert has_element?(view, "#screen-#{room.id}[data-main=true]")
      assert has_element?(view, "#screen-other[data-main=false]")
      assert has_element?(view, "#watching", "Elden Ring")
      assert has_element?(view, "#watching", "Shared by Luca")
      refute has_element?(view, "#screen-#{room.id} button[phx-click=watch]")

      view |> element("#screen-other button[phx-click=watch]") |> render_click()

      assert has_element?(view, "#screen-other[data-main=true]")
      assert has_element?(view, "#screen-#{room.id}[data-main=false]")
      assert has_element?(view, "#watching", "Hades")
      assert has_element?(view, "#watching", "Shared by Bia")
    end

    test "only lets big screens pause, change the volume and go full screen",
         %{conn: conn, room: room} do
      other = %{room | id: "other", title: "Hades", started_at: DateTime.utc_now()}

      {:ok, view, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)
      Screens.broadcast(%{other | live?: true}, :live)

      # Without the browser's controls, clicking the picture doesn't pause it
      refute has_element?(view, "video[controls]")

      controls = "#screen-viewer-controls-#{room.id}"
      assert has_element?(view, "#{controls}[data-muted][data-pointer-menu]")
      assert has_element?(view, "#{controls} [data-video-play]")
      assert has_element?(view, "#{controls} [data-video-mute]")
      assert has_element?(view, "#{controls} input[type=range][data-video-volume]")
      assert has_element?(view, "#{controls} [data-video-fullscreen]")

      # Clicking a small screen watches it instead
      assert has_element?(view, "#screen-other .hidden > #screen-viewer-controls-other")
      refute has_element?(view, ".hidden > #{controls}")
    end

    test "goes back to the first screen when the watched one ends", %{conn: conn, room: room} do
      other = %{room | id: "other", title: "Hades", started_at: DateTime.utc_now()}
      {:ok, view, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)
      Screens.broadcast(%{other | live?: true}, :live)

      view |> element("#screen-other button[phx-click=watch]") |> render_click()
      Screens.broadcast(other, :ended)

      assert has_element?(view, "#screen-#{room.id}[data-main=true]")
      assert has_element?(view, "#watching", "Elden Ring")
    end

    test "can't watch rooms that aren't on the page", %{conn: conn, room: room} do
      {:ok, view, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)

      render_click(view, "watch", %{"room_id" => "missing"})

      assert has_element?(view, "#screen-#{room.id}[data-main=true]")
    end

    test "pins screens to keep several big", %{conn: conn, room: room} do
      other = %{
        room
        | id: "other",
          title: "Hades",
          owner_name: "Bia",
          started_at: DateTime.utc_now()
      }

      third = %{room | id: "third", title: "Celeste", started_at: DateTime.utc_now()}

      {:ok, view, _html} = live_guild(conn, "1")

      for r <- [room, other, third], do: Screens.broadcast(%{r | live?: true}, :live)

      # The only big screen can't be unpinned
      refute has_element?(view, "#screen-#{room.id} button[phx-click=pin]")

      view |> element("#screen-other button[phx-click=pin]") |> render_click()

      assert has_element?(view, "#screen-#{room.id}[data-main=true]")
      assert has_element?(view, "#screen-other[data-main=true]")
      assert has_element?(view, "#screen-third[data-main=false]")
      assert has_element?(view, "#watching", "Watching 2 screens")
      assert has_element?(view, "#screen-other", "Hades · Bia")
      assert has_element?(view, "#screen-other button[phx-click=pin][aria-pressed=true]")
      assert has_element?(view, "#screen-third button[phx-click=pin][aria-pressed=false]")

      view |> element("#screen-#{room.id} button[phx-click=pin]") |> render_click()

      assert has_element?(view, "#screen-#{room.id}[data-main=false]")
      assert has_element?(view, "#screen-other[data-main=true]")
      assert has_element?(view, "#watching", "Hades")
      refute has_element?(view, "#screen-other button[phx-click=pin]")

      # Watching a screen from the strip makes it the only big one again
      view |> element("#screen-third button[phx-click=pin]") |> render_click()
      view |> element("#screen-#{room.id} button[phx-click=watch]") |> render_click()

      assert has_element?(view, "#screen-#{room.id}[data-main=true]")
      assert has_element?(view, "#screen-other[data-main=false]")
      assert has_element?(view, "#screen-third[data-main=false]")
    end

    test "forgets pins of rooms that ended", %{conn: conn, room: room} do
      other = %{room | id: "other", title: "Hades", started_at: DateTime.utc_now()}
      third = %{room | id: "third", title: "Celeste", started_at: DateTime.utc_now()}
      {:ok, view, _html} = live_guild(conn, "1")

      for r <- [room, other, third], do: Screens.broadcast(%{r | live?: true}, :live)

      view |> element("#screen-other button[phx-click=pin]") |> render_click()
      view |> element("#screen-third button[phx-click=pin]") |> render_click()
      Screens.broadcast(other, :ended)

      assert has_element?(view, "#screen-#{room.id}[data-main=true]")
      assert has_element?(view, "#screen-third[data-main=true]")
      assert has_element?(view, "#watching", "Watching 2 screens")
    end

    test "can't pin rooms that aren't on the page", %{conn: conn, room: room} do
      {:ok, view, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)

      render_click(view, "pin", %{"room_id" => "missing"})

      assert has_element?(view, "#screen-#{room.id}[data-main=true]")
      assert has_element?(view, "#watching", "Elden Ring")
    end

    test "doesn't show how many are watching", %{conn: conn, room: room} do
      view = live_guild_with_room(conn, room)

      Screens.broadcast(%{room | live?: true, viewer_count: 2}, :updated)

      refute render(view) =~ "2 viewers"
    end

    test "has the soundboard, the pointer and the chat in the bar", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")

      assert has_element?(view, "#screen-bar #soundboard-toggle[aria-controls=soundboard-panel]")
      assert has_element?(view, "#screen-bar #soundboard-panel[hidden]")
      assert has_element?(view, "#screen-bar #pointer-toggle[aria-controls=pointer-panel]")
      assert has_element?(view, "#screen-bar #chat-toggle[aria-pressed=true]")
    end

    test "lists who is online in a popover", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")

      assert has_element?(view, "#online-toggle[aria-controls=online-list]", "1 online")
      assert has_element?(view, "#online-list[hidden]")
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

      assert has_element?(view, "#online-list", "Online · 1")
      refute has_element?(view, "#online-11")
      refute has_element?(view, "#online-12")
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

    test "chimes for the streamer when viewers join and leave", %{conn: conn, room: room} do
      view = conn |> log_in_as(room.owner_id, room.owner_name) |> live_guild_with_room(room)

      Screens.broadcast(%{room | live?: true, viewer_count: 1}, :updated)
      assert_push_event(view, "screen:viewer_joined", %{})

      Screens.broadcast(%{room | live?: true, viewer_count: 0}, :updated)
      assert_push_event(view, "screen:viewer_left", %{})

      Screens.broadcast(%{room | live?: true, viewer_count: 0, title: "Hades"}, :updated)
      assert render(view) =~ "Hades"
      refute_push_event(view, "screen:viewer_joined", %{}, 50)
      refute_push_event(view, "screen:viewer_left", %{}, 50)
    end

    test "doesn't chime for other members", %{conn: conn, room: room} do
      view = live_guild_with_room(conn, room)

      Screens.broadcast(%{room | live?: true, viewer_count: 1}, :updated)
      render(view)

      refute_push_event(view, "screen:viewer_joined", %{}, 50)
    end

    test "only chimes for the streamer's own room", %{conn: conn, room: room} do
      other = %{room | id: "other", owner_id: "4", started_at: DateTime.utc_now()}
      view = conn |> log_in_as(room.owner_id, room.owner_name) |> live_guild_with_room(room)
      Screens.broadcast(%{other | live?: true}, :live)

      Screens.broadcast(%{other | live?: true, viewer_count: 1}, :updated)
      render(view)

      refute_push_event(view, "screen:viewer_joined", %{}, 50)
    end

    test "doesn't show other guilds' rooms", %{conn: conn, room: room} do
      {:ok, view, _html} = live_guild(conn, "9")

      Screens.broadcast(%{room | live?: true}, :live)

      refute render(view) =~ "Elden Ring"
    end

    test "replies with an error to invalid offers", %{conn: conn, room: room} do
      view = live_guild_with_room(conn, room)

      render_hook(view, "offer", %{"room_id" => room.id, "type" => "offer"})

      assert_reply(view, %{error: "Couldn't connect to the screen share"})
    end

    test "only connects to rooms on the page", %{conn: conn, room: room} do
      {:ok, view, _html} = live_guild(conn, "1")

      render_hook(view, "offer", %{"room_id" => room.id, "type" => "offer", "sdp" => ""})

      assert_reply(view, %{error: "Couldn't connect to the screen share"})
    end
  end

  describe "ads" do
    defp live_ads(conn) do
      {:ok, view, _html} = live(conn, ~p"/screens/1")
      view
    end

    defp shown_ad(view) do
      [_match, id] = Regex.run(~r/id="ad" data-ad="([^"]+)"/, render(view))
      id
    end

    defp choose(view, selector), do: view |> element(selector) |> render_click()

    test "are shown in the strip's row, without the admins' menu", %{conn: conn} do
      view = live_ads(conn)

      assert has_element?(view, "#ad.row-start-\\(--strip-row\\) img[src^='/images/ads/']")
      refute has_element?(view, "#billboard-toggle")
    end

    test "can be hidden and shown again by admins, for everyone", %{conn: conn} do
      patch_function(Discord, :check_member, :admin)
      admin = live_ads(conn)
      {:ok, member, _html} = live(log_in_as(build_conn(), "11", "Bia"), ~p"/screens/1")

      assert has_element?(admin, "#billboard-toggle[aria-pressed=true]")
      assert has_element?(admin, "[data-billboard-mode=random][aria-pressed=true]")

      choose(admin, "[data-billboard-mode=hidden]")

      assert Screens.get_settings("1").ads_mode == :hidden
      refute has_element?(admin, "#ad")
      assert has_element?(admin, "#billboard-toggle[aria-pressed=false]")
      eventually(fn -> refute has_element?(member, "#ad") end)

      # New pages remember it
      refute has_element?(live_ads(conn), "#ad")

      choose(admin, "[data-billboard-mode=random]")

      assert Screens.get_settings("1").ads_mode == :random
      eventually(fn -> assert has_element?(member, "#ad") end)
    end

    test "can be set to one ad by admins, for everyone", %{conn: conn} do
      patch_function(Discord, :check_member, :admin)
      admin = live_ads(conn)
      {:ok, member, _html} = live(log_in_as(build_conn(), "11", "Bia"), ~p"/screens/1")

      for id <- ["riftbound-cards", "dopamine-course"] do
        choose(admin, "[data-billboard-pick=#{id}]")

        assert has_element?(admin, "[data-billboard-pick=#{id}][aria-pressed=true]")
        assert shown_ad(admin) == id
        eventually(fn -> assert shown_ad(member) == id end)
        assert shown_ad(live_ads(conn)) == id
      end

      assert %{ads_mode: :fixed, ad_id: "dopamine-course"} = Screens.get_settings("1")
    end

    test "change every minute when admins choose so", %{conn: conn} do
      patch_function(Discord, :check_member, :admin)
      view = live_ads(conn)

      choose(view, "[data-billboard-mode=rotating]")
      first = shown_ad(view)

      send(view.pid, {:ads, :rotate})
      second = shown_ad(view)
      assert second != first
      assert second in Enum.map(Ads.all(), & &1.id)

      # Stops once they choose something else
      choose(view, "[data-billboard-pick=#{first}]")
      send(view.pid, {:ads, :rotate})
      assert shown_ad(view) == first
    end

    test "start from the same ad on every page while changing", %{conn: conn} do
      {:ok, _settings} = Screens.set_ads("1", :rotating)

      assert shown_ad(live_ads(conn)) == shown_ad(live_ads(conn))
    end

    test "can't be changed by members", %{conn: conn} do
      view = live_ads(conn)

      render_hook(view, "ads:set", %{"mode" => "hidden"})

      assert Screens.get_settings("1").ads_mode == :random
      assert has_element?(view, "#ad")
    end

    test "ignore choices that aren't in the menu", %{conn: conn} do
      patch_function(Discord, :check_member, :admin)
      view = live_ads(conn)

      render_hook(view, "ads:set", %{"mode" => "fixed", "ad" => "nope"})
      render_hook(view, "ads:set", %{"mode" => "loud"})

      assert Screens.get_settings("1").ads_mode == :random
    end

    test "are only changed in the guild they were changed in" do
      {:ok, _settings} = Screens.set_ads("1", :hidden)

      assert Screens.get_settings("1").ads_mode == :hidden
      assert Screens.get_settings("2").ads_mode == :random
    end
  end

  describe "soundboard" do
    defp play(view, sound_id),
      do: view |> element("#soundboard button[phx-value-sound=#{sound_id}]") |> render_click()

    test "plays sounds for everyone on the guild's pages", %{conn: conn, room: room} do
      {:ok, watch, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(log_in(build_conn()), "1")
      Screens.broadcast(%{room | live?: true}, :live)

      play(watch, "volibero")

      assert_push_event(watch, "sound:play", %{
        id: "volibero",
        emoji: "🐻",
        url: "/sounds/volibero.mp3"
      })

      assert_push_event(other, "sound:play", %{id: "volibero"})
    end

    test "works while nobody is sharing", %{conn: conn, room: room} do
      Screens.stop_room(room)
      {:ok, guild, html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(conn, "1")

      assert html =~ "Nobody is sharing their screen right now"
      play(guild, "mj")

      assert_push_event(other, "sound:play", %{id: "mj"})
    end

    test "stops the sound for everyone", %{conn: conn} do
      {:ok, watch, _html} = live_guild(conn, "1")
      {:ok, guild, _html} = live_guild(conn, "1")

      watch |> element("#soundboard button[phx-click='sound:stop']") |> render_click()

      assert_push_event(watch, "sound:stop", %{})
      assert_push_event(guild, "sound:stop", %{})
    end

    test "doesn't play sounds for other guilds", %{conn: conn} do
      {:ok, watch, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(conn, "9")

      play(watch, "volibero")

      assert_push_event(watch, "sound:play", %{id: "volibero"})
      refute_push_event(other, "sound:play", %{})
    end

    test "waits after three sounds in a row", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")

      for _ <- 1..3, do: play(view, "scooby-doo")

      assert has_element?(view, "#soundboard [data-sounds-cooldown]")
      assert has_element?(view, "#soundboard button[phx-value-sound=scooby-doo][disabled]")

      # Clicks during the cooldown, e.g. from a stale page, don't play
      render_click(view, "sound:play", %{"sound" => "scooby-doo"})
      for _ <- 1..3, do: assert_push_event(view, "sound:play", %{id: "scooby-doo"})
      refute_push_event(view, "sound:play", %{})
    end

    test "ignores unknown sounds", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")

      render_click(view, "sound:play", %{"sound" => "missing"})

      refute_push_event(view, "sound:play", %{})
    end
  end

  describe "chat" do
    defp say(view, text), do: view |> element("#chat-form") |> render_submit(%{"text" => text})

    test "sends messages to everyone on the guild's page", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, other, _html} = conn |> log_in_as("11", "Bia") |> live_guild("1")

      say(other, "gg")

      eventually(fn ->
        for page <- [view, other], do: assert(has_element?(page, "#chat-lines li", "Bia gg"))
      end)
    end

    test "doesn't reach other guilds", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(conn, "9")

      say(view, "only here")

      eventually(fn -> assert has_element?(view, "#chat-lines", "only here") end)
      refute has_element?(other, "#chat-lines", "only here")
    end

    test "only shows the latest lines", %{conn: conn} do
      for number <- 1..10, do: Activity.record("1", :sound, "Bia", "sound #{number}")
      {:ok, view, _html} = live_guild(conn, "1")

      # Someone joining can also be among them
      assert has_element?(view, "#chat-lines", "sound 10")
      assert has_element?(view, "#chat-lines", "sound 6")
      refute has_element?(view, "#chat-lines", "sound 4")
    end

    test "asks to slow down after a few messages in a row", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")

      for number <- 1..6, do: say(view, "message #{number}")

      assert has_element?(view, "#chat", "Slow down")
      eventually(fn -> assert has_element?(view, "#chat-lines", "message 5") end)
      refute has_element?(view, "#chat-lines", "message 6")
    end

    test "counts the others' messages while hidden", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, other, _html} = conn |> log_in_as("11", "Bia") |> live_guild("1")

      view |> element("#chat-toggle") |> render_click()
      refute has_element?(view, "#chat")
      assert has_element?(view, "#chat-toggle[aria-pressed=false]")

      # The box is hidden with the chat, but a message could still come from a stale page
      render_hook(view, "chat:send", %{"text" => "mine"})
      say(other, "one")
      say(other, "two")

      eventually(fn -> assert has_element?(view, "#chat-unread", "2") end)

      view |> element("#chat-toggle") |> render_click()
      assert has_element?(view, "#chat-lines", "two")
      refute has_element?(view, "#chat-unread")
    end
  end

  describe "music" do
    # yt-dlp finds a song titled like the search, and "downloads" a tiny file
    setup do
      Jukebox.stop("1")
      on_exit(fn -> Jukebox.stop("1") end)

      patch_function(YtDlp, :lookup, fn
        "nothing" ->
          {:error, :not_found}

        term ->
          {:ok,
           %{
             id: "abcdefghijk",
             title: term,
             url: "https://www.youtube.com/watch?v=abcdefghijk",
             thumbnail: "https://i.ytimg.com/vi/abcdefghijk/mqdefault.jpg",
             duration_ms: 187_000,
             channel: nil
           }}
      end)

      patch_function(YtDlp, :download, fn _url, dir, name ->
        path = Path.join(dir, "#{name}.m4a")
        File.write!(path, "audio")
        {:ok, path}
      end)

      :ok
    end

    defp add_song(view, term),
      do: view |> element("#music-form") |> render_submit(%{"term" => term})

    defp song_playing(view, title) do
      eventually(fn ->
        assert has_element?(view, "#music-title", title)
        assert has_element?(view, "#music-toggle[aria-pressed=true]")
      end)
    end

    test "is a button in the bar, with nothing playing", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")

      assert has_element?(view, "#screen-bar #music-toggle[aria-controls=music-panel]")
      assert has_element?(view, "#screen-bar #music-panel[hidden]")
      assert has_element?(view, "#music-now", "Nothing playing")
      assert has_element?(view, "#music-play[disabled]")
      assert has_element?(view, "#music-queue", "The queue is empty")
    end

    test "plays the songs anyone adds for everyone on the page", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(log_in_as("11", "Bia"), "1")

      add_song(view, "never gonna give you up")
      add_song(other, "careless whisper")

      for page <- [view, other] do
        song_playing(page, "never gonna give you up")
        assert has_element?(page, "#music-now", "Added by Ana")
        assert has_element?(page, "#music-now", "3:07")

        assert has_element?(
                 page,
                 "#music-now img[src='https://i.ytimg.com/vi/abcdefghijk/mqdefault.jpg']"
               )

        eventually(fn -> assert has_element?(page, "#music-queue li", "careless whisper") end)
        assert has_element?(page, "#music-queue", "Bia")
      end

      %{current: %{id: id}} = Jukebox.state("1")
      src = "/screens/1/music/#{id}"

      assert_push_event(other, "music:sync", %{
        track: ^id,
        src: ^src,
        playing: true,
        duration: 187_000
      })

      eventually(fn -> assert has_element?(view, "#chat-lines", "Bia added careless whisper") end)
    end

    test "shows the page that added a song when nothing was found", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(log_in_as("11", "Bia"), "1")

      add_song(view, "nothing")

      eventually(fn -> assert has_element?(view, "#music-error", "Nothing found on YouTube") end)
      refute has_element?(other, "#music-error")
      refute has_element?(view, "#music-queue li")
    end

    test "can be paused and skipped by anyone", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      add_song(view, "one")
      add_song(view, "two")
      song_playing(view, "one")

      view |> element("#music-play") |> render_click()

      eventually(fn -> assert has_element?(view, "#music-toggle[aria-pressed=false]") end)
      assert has_element?(view, "#music-play[title=Play]")
      assert_push_event(view, "music:sync", %{playing: false})

      view |> element("button[phx-click='music:next']") |> render_click()

      song_playing(view, "two")
      eventually(fn -> assert has_element?(view, "#chat-lines", "Ana skipped one") end)

      view |> element("button[phx-click='music:previous']") |> render_click()

      song_playing(view, "one")
    end

    test "lets admins remove songs from the queue", %{conn: conn} do
      patch_function(Discord, :check_member, :admin)
      {:ok, view, _html} = live_guild(conn, "1")
      add_song(view, "one")
      add_song(view, "two")
      song_playing(view, "one")
      %{queue: [two]} = Jukebox.state("1")

      view |> element("#music-track-#{two.id} button[phx-click='music:remove']") |> render_click()

      eventually(fn -> refute has_element?(view, "#music-track-#{two.id}") end)
    end

    test "doesn't let members remove songs", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      add_song(view, "one")
      add_song(view, "two")
      song_playing(view, "one")
      %{queue: [two]} = Jukebox.state("1")

      refute has_element?(view, "button[phx-click='music:remove']")

      render_click(view, "music:remove", %{"track" => two.id})

      assert [%{title: "two"}] = Jukebox.state("1").queue
    end

    test "is only heard in its own guild", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(conn, "9")

      add_song(view, "one")

      song_playing(view, "one")
      assert has_element?(other, "#music-now", "Nothing playing")
    end
  end

  describe "pointers" do
    @move %{
      "a" => %{"k" => "p", "i" => "guild:1"},
      "p" => [[0.5, 0.25, 1_000, 0], [0.52, 0.3, 1_016, 1]],
      "c" => 3,
      "st" => "sparkle",
      "w" => 12
    }

    defp log_in_as(id, name),
      do: init_test_session(build_conn(), %{"discord_user_id" => id, "discord_user_name" => name})

    test "relays pointers to the guild's other pages, saying whose they are",
         %{conn: conn} do
      {:ok, watch, _html} = live_guild(conn, "1")
      {:ok, guild, _html} = live_guild(log_in_as("11", "Bia"), "1")

      render_hook(watch, "pointer:move", @move)

      assert_push_event(guild, "pointer:move", %{
        u: "10",
        n: "Ana",
        s: sender,
        a: %{k: "p", i: "guild:1"},
        p: [[0.5, 0.25, 1_000, 0], [0.52, 0.3, 1_016, 1]],
        c: 3,
        st: "sparkle",
        w: 12
      })

      assert is_binary(sender)
      # The page drawing it already shows its own pointer
      refute_push_event(watch, "pointer:move", %{})
    end

    test "tells pages apart when a member has several open", %{conn: conn} do
      {:ok, first, _html} = live_guild(conn, "1")
      {:ok, second, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(log_in_as("11", "Bia"), "1")

      render_hook(first, "pointer:move", @move)
      render_hook(second, "pointer:move", @move)

      assert_push_event(other, "pointer:move", %{u: "10", s: first_sender})
      assert_push_event(other, "pointer:move", %{u: "10", s: second_sender})
      assert first_sender != second_sender
    end

    test "doesn't relay pointers to other guilds", %{conn: conn} do
      {:ok, watch, _html} = live_guild(conn, "1")
      {:ok, other_guild, _html} = live_guild(log_in_as("11", "Bia"), "9")

      render_hook(watch, "pointer:move", @move)

      refute_push_event(other_guild, "pointer:move", %{})
    end

    test "ignores invalid pointers", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(log_in_as("11", "Bia"), "1")

      render_hook(view, "pointer:move", %{@move | "st" => "blink"})
      render_hook(view, "pointer:move", %{@move | "p" => [[99, 0.5, 1_000, 0]]})

      render_hook(view, "pointer:effect", %{
        "e" => "nuke",
        "a" => @move["a"],
        "x" => 0.5,
        "y" => 0.5
      })

      refute_push_event(other, "pointer:move", %{})
      refute_push_event(other, "pointer:effect", %{})
    end

    test "relays pointers being turned off", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(log_in_as("11", "Bia"), "1")

      render_hook(view, "pointer:off", %{})

      assert_push_event(other, "pointer:off", %{u: "10", s: _sender})
    end

    test "relays special effects, a few seconds apart", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")
      {:ok, other, _html} = live_guild(log_in_as("11", "Bia"), "1")
      effect = %{"e" => "heart", "a" => @move["a"], "x" => 0.5, "y" => 1.5}

      render_hook(view, "pointer:effect", effect)
      render_hook(view, "pointer:effect", %{effect | "e" => "star"})

      assert_push_event(other, "pointer:effect", %{e: "heart", u: "10", x: 0.5, y: 1.5})
      refute_push_event(other, "pointer:effect", %{e: "star"})
    end

    test "sounds say who played them, so they can be muted", %{conn: conn} do
      {:ok, view, _html} = live_guild(conn, "1")

      view |> element("#soundboard button[phx-value-sound=mj]") |> render_click()

      assert_push_event(view, "sound:play", %{id: "mj", by: "10"})
    end

    test "the online list can mute the others, but not yourself", %{conn: conn} do
      {:ok, _other, _html} = live_guild(log_in_as("11", "Bia"), "1")
      {:ok, view, _html} = live_guild(conn, "1")

      assert has_element?(view, "#online-11 button[data-mute-user='11'][data-mute='sounds']")
      assert has_element?(view, "#online-11 button[data-mute-user='11'][data-mute='pointer']")
      refute has_element?(view, "#online-10 button[data-mute-user]")
    end

    test "streams are covered while drawing, but not their controls", %{conn: conn, room: room} do
      {:ok, view, _html} = live_guild(conn, "1")
      Screens.broadcast(%{room | live?: true}, :live)

      assert has_element?(view, "#screen-viewer-#{room.id} [data-pointer-shield].bottom-12")
    end
  end

  describe "managing your own stream" do
    defp live_manage(conn) do
      {:ok, manage, _html} = live(conn, ~p"/screens/1/share")
      manage
    end

    defp my_room, do: Screens.find_owner_room("1", "10")

    setup do
      on_exit(fn -> if room = my_room(), do: Screens.stop_room(room) end)
    end

    test "is linked from the guild page's header, opening a new tab", %{conn: conn} do
      {:ok, guild, _html} = live(conn, ~p"/screens/1")

      assert has_element?(
               guild,
               "#share-link[href='/screens/1/share'][target=_blank]",
               "Share my screen"
             )

      refute has_element?(guild, "#manage-stream")
    end

    test "has the controls to share a screen", %{conn: conn} do
      manage = live_manage(conn)

      assert has_element?(manage, "h1", "Share your screen")
      assert has_element?(manage, "#watch-link[href='/screens/1'][target=_blank]")
      assert has_element?(manage, "[data-screen-start]", "Share screen")
      assert has_element?(manage, "[data-screen-switch]")
      assert has_element?(manage, "[data-screen-stop]")
      assert has_element?(manage, "#manage-stream-title-input")
    end

    test "keeps other people out", %{conn: conn} do
      patch_function(Discord, :check_member, :not_member)

      manage = live_manage(conn)

      assert render(manage) =~ "Not in this server"
      refute has_element?(manage, "[data-screen-start]")
    end

    test "only works for real guilds", %{conn: conn} do
      {:ok, manage, _html} = live(conn, ~p"/screens/abc/share")

      assert render(manage) =~ "Server not found"
    end

    test "needs a login" do
      conn = get(build_conn(), ~p"/screens/1/share")

      assert redirected_to(conn) == "/auth/login?return_to=%2Fscreens%2F1%2Fshare"
    end

    test "doesn't make a room until something is picked to share", %{conn: conn} do
      live_manage(conn)

      assert my_room() == nil
    end

    test "makes the member's room, without a channel to announce in, once they pick a source",
         %{conn: conn} do
      manage = live_manage(conn)

      render_hook(manage, "source", %{"surface" => "window"})

      assert %{owner_id: "10", owner_name: "Ana", channel_id: nil, live?: false} = my_room()
      assert my_room().source == :window
      assert my_room().title == "Ana's window"
    end

    test "keeps the title typed before sharing", %{conn: conn} do
      manage = live_manage(conn)

      manage
      |> element("#manage-stream-title")
      |> render_change(%{"title" => "Elden Ring night"})

      render_hook(manage, "source", %{"surface" => "monitor"})

      assert %{title: "Elden Ring night", custom_title?: true} = my_room()
    end

    test "renames the room while sharing", %{conn: conn} do
      manage = live_manage(conn)
      render_hook(manage, "source", %{"surface" => "monitor"})

      manage |> element("#manage-stream-title") |> render_change(%{"title" => "Boss fight"})

      assert my_room().title == "Boss fight"
    end

    test "stops the room", %{conn: conn} do
      manage = live_manage(conn)
      render_hook(manage, "source", %{"surface" => "monitor"})
      room_id = my_room().id

      render_hook(manage, "stop", %{})

      assert Screens.get_room(room_id) == nil
      assert_push_event(manage, "screen:ended", %{})
    end

    test "finds the room again when the page reloads", %{conn: conn} do
      manage = live_manage(conn)
      render_hook(manage, "source", %{"surface" => "monitor"})
      room_id = my_room().id

      manage = live_manage(conn)
      render_hook(manage, "source", %{"surface" => "window"})

      assert my_room().id == room_id
      assert my_room().source == :window
    end

    test "tells the member's browser when viewers join and leave", %{conn: conn} do
      manage = live_manage(conn)
      render_hook(manage, "source", %{"surface" => "monitor"})
      room = my_room()

      Screens.broadcast(%{room | viewer_count: 2}, :updated)
      assert_push_event(manage, "screen:viewer_joined", %{})

      Screens.broadcast(%{room | viewer_count: 2, title: "Speedrun"}, :updated)
      refute_push_event(manage, "screen:viewer_joined", %{}, 50)

      Screens.broadcast(%{room | viewer_count: 1}, :updated)
      assert_push_event(manage, "screen:viewer_left", %{})
    end

    test "marks the guild page's link live while the member is sharing", %{conn: conn} do
      {:ok, guild, _html} = live(conn, ~p"/screens/1")
      manage = live_manage(conn)
      render_hook(manage, "source", %{"surface" => "monitor"})

      refute has_element?(guild, "#share-link", "LIVE")

      Screens.broadcast(%{my_room() | live?: true}, :live)

      assert has_element?(guild, "#share-link", "Manage my stream")
      assert has_element?(guild, "#share-link", "LIVE")
    end

    test "never touches other members' rooms", %{conn: conn, room: room} do
      manage = live_manage(conn)

      render_hook(manage, "source", %{"surface" => "monitor"})

      assert my_room().id != room.id
      assert Screens.find_owner_room("1", "3").id == room.id
    end

    test "asks to stop OBS before sharing from here", %{conn: conn} do
      manage = live_manage(conn)
      render_hook(manage, "source", %{"surface" => "monitor"})

      Screens.broadcast(%{my_room() | live?: true, source: :obs}, :updated)

      assert has_element?(manage, "p", "sharing from OBS")
      refute has_element?(manage, "[data-screen-start]")
    end
  end
end
