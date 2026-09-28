defmodule BotchiniDiscordTest.ScreensTest do
  use ExUnit.Case, async: false

  use Patch

  @moduletag :capture_log

  alias Ecto.Adapters.SQL.Sandbox
  alias Nostrum.Error.ApiError
  alias Nostrum.Struct.{Guild.Member, Interaction, User}

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias BotchiniDiscord.Helpers
  alias BotchiniDiscord.Screens.Announcer
  alias BotchiniDiscord.Screens.Interactions.Screen

  setup do
    # The announcer reads the streams channels from its own process
    :ok = Sandbox.checkout(Botchini.Repo)
    Sandbox.mode(Botchini.Repo, {:shared, self()})

    on_exit(fn ->
      for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(Screens.RoomSupervisor) do
        DynamicSupervisor.terminate_child(Screens.RoomSupervisor, pid)
      end
    end)
  end

  defp interaction(user_id \\ 3) do
    %Interaction{
      guild_id: 1,
      channel_id: 2,
      user: %User{id: user_id, username: "luca", global_name: "Luca"},
      member: %Member{user_id: user_id, nick: nil}
    }
  end

  defp subcommand(name), do: [%{name: name, value: "", focused: false}]

  defp buttons(response) do
    Enum.flat_map(response.data.components, & &1.components)
  end

  describe "/stream start" do
    test "privately sends the broadcast and watch all links" do
      response = Screen.handle_interaction(interaction(), subcommand("start"))

      assert response.data.flags == 64
      assert response.data.content =~ "**Luca's screen**"

      room = Screens.find_owner_room("1", "3")
      assert %Room{title: "Luca's screen", channel_id: "2", owner_name: "Luca"} = room

      assert [broadcast, watch_all] = buttons(response)
      assert broadcast.url =~ ~r"/screens/#{room.id}/broadcast##{room.broadcast_key}$"
      assert watch_all.label == "Watch all"
      assert watch_all.url =~ ~r"/screens#.+$"
      refute watch_all.url =~ room.broadcast_key
    end

    test "points to the streams channel when the server has one" do
      {:ok, _stream_channel} = Screens.put_stream_channel("1", "5", "30")

      response = Screen.handle_interaction(interaction(), subcommand("start"))

      assert response.data.content =~ "I'll list you in <#5> once you're live"
    end

    test "sends the running room's links again" do
      first = Screen.handle_interaction(interaction(), subcommand("start"))
      response = Screen.handle_interaction(interaction(), subcommand("start"))

      # The watch all link is signed again on every reply
      assert [broadcast, %{label: "Watch all"}] = buttons(response)
      assert [^broadcast, _watch_all] = buttons(first)
      assert length(Screens.list_rooms("1")) == 1
    end
  end

  describe "/stream stop" do
    test "ends the user's room" do
      Screen.handle_interaction(interaction(), subcommand("start"))
      response = Screen.handle_interaction(interaction(), subcommand("stop"))

      assert response.data.content =~ "Stopped sharing"
      assert Screens.find_owner_room("1", "3") == nil
    end

    test "doesn't end other users' rooms" do
      Screen.handle_interaction(interaction(4), subcommand("start"))
      response = Screen.handle_interaction(interaction(), subcommand("stop"))

      assert response.data.content == "You're not sharing your screen"
      assert Screens.find_owner_room("1", "4")
    end
  end

  test "/stream obs privately sends a stream key for OBS" do
    response = Screen.handle_interaction(interaction(), subcommand("obs"))

    assert response.data.flags == 64
    assert response.data.content =~ "/api/whip`"
    assert [_match, key] = Regex.run(~r/\|\|`(.+)`\|\|/, response.data.content)
    assert %{discord_user_id: "3", discord_channel_id: "2"} = Screens.get_stream_key(key)
  end

  test "/stream watch only shows rooms that are live" do
    Screen.handle_interaction(interaction(), subcommand("start"))
    response = Screen.handle_interaction(interaction(), subcommand("watch"))

    assert response.data.content =~ "Nobody is sharing their screen right now"
    assert [%{label: "Watch all", url: url}] = buttons(response)
    assert url =~ ~r"/screens#.+$"
  end

  test "/stream watch names every live room and only links to all of them" do
    Screen.handle_interaction(interaction(), subcommand("start"))
    room = Screens.find_owner_room("1", "3")
    patch(Screens, :list_rooms, [%{room | live?: true}])

    response = Screen.handle_interaction(interaction(), subcommand("watch"))

    assert response.data.content =~ "**Luca's screen** by <@3>"
    assert [%{label: "Watch all", url: url}] = buttons(response)
    assert url =~ ~r"/screens#.+$"
    refute url =~ room.id
  end

  test "/stream channel needs the Manage Server permission" do
    patch(Helpers, :manage_guild?, false)

    response = Screen.handle_interaction(interaction(), subcommand("channel"))

    assert response.data.flags == 64
    assert response.data.content =~ "Manage Server"
    assert Screens.get_stream_channel("1") == nil
  end

  test "can only be used inside a server" do
    response = Screen.handle_interaction(%{interaction() | member: nil}, subcommand("watch"))

    assert response.data.content == "Can only be used inside a server!"
  end

  describe "Announcer" do
    setup do
      # Stubs the HTTP request instead of Message.create/2, so Nostrum still
      # prepares the payloads like it would for Discord
      patch(Nostrum.Api, :request, callable(&discord/1, dispatch: :list))
      start_supervised!(Announcer)

      room = %Room{
        id: "room",
        broadcast_key: "key",
        title: "Elden Ring",
        guild_id: "1",
        channel_id: "2",
        owner_id: "3",
        owner_name: "Luca",
        started_at: DateTime.utc_now()
      }

      %{room: room}
    end

    test "posts the watch all link once live, and deletes it once ended", %{room: room} do
      Screens.broadcast(room, :live)
      Screens.broadcast(room, :ended)
      # Syncs with the announcer, so both events were handled
      :sys.get_state(Announcer)

      assert_called(Nostrum.Api.request(:post, "/channels/2/messages", live))
      assert live.content =~ "<@3> is sharing their screen: **Elden Ring**"
      assert live.allowed_mentions == %{parse: []}
      assert [%{components: [%{label: "Watch all", url: url}]}] = live.components
      assert url =~ ~r"/screens#.+$"
      refute url =~ "/screens/room"

      assert_called(Nostrum.Api.request(:delete, "/channels/2/messages/20"))
    end

    test "updates the live message when the title changes", %{room: room} do
      Screens.broadcast(room, :live)
      :sys.get_state(Announcer)
      Screens.broadcast(%{room | viewer_count: 2}, :updated)
      Screens.broadcast(%{room | title: "Boss *fight*"}, :updated)
      :sys.get_state(Announcer)

      assert_called_once(Nostrum.Api.request(:patch, "/channels/2/messages/20", edited))
      assert edited.content =~ "**Boss \\*fight\\***"
      assert [%{components: [%{label: "Watch all"}]}] = edited.components
    end

    test "tells the broadcaster when it can't post the watch link", %{room: room} do
      error = %ApiError{
        status_code: 403,
        response: %{code: 50_013, message: "Missing Permissions"}
      }

      patch(Nostrum.Api, :request, {:error, error})
      Screens.subscribe(room.id)

      Screens.broadcast(room, :live)

      assert_receive {:screen_announcement_failed, "room"}
      assert Process.alive?(Process.whereis(Announcer))
    end

    test "only announces rooms that went live", %{room: room} do
      Screens.broadcast(room, :updated)
      Screens.broadcast(room, :ended)
      :sys.get_state(Announcer)

      refute_called(Nostrum.Api.request(_method, _route, _body))
    end

    test "/stream channel posts the list of screen shares in the channel", %{room: room} do
      patch(Helpers, :manage_guild?, true)
      Screens.broadcast(room, :live)
      :sys.get_state(Announcer)
      patch(Screens, :list_rooms, [%{room | live?: true}])

      response =
        Screen.handle_interaction(%{interaction() | channel_id: 5}, subcommand("channel"))

      assert response.data.content =~ "I'll keep the list of screen shares in this channel"

      assert %{discord_channel_id: "5", discord_message_id: "20"} =
               Screens.get_stream_channel("1")

      # The room's message where it was started moves to the list
      assert_called(Nostrum.Api.request(:delete, "/channels/2/messages/20"))
      assert_called(Nostrum.Api.request(:post, "/channels/5/messages", status))
      assert status.content =~ "🔴 **Elden Ring** by <@3>"
      assert [%{components: [%{label: "Watch all"}]}] = status.components
    end

    test "/stream channel says when it can't post in the channel" do
      patch(Helpers, :manage_guild?, true)

      patch(
        Nostrum.Api,
        :request,
        {:error,
         %ApiError{status_code: 403, response: %{code: 50_001, message: "Missing Access"}}}
      )

      response =
        Screen.handle_interaction(%{interaction() | channel_id: 5}, subcommand("channel"))

      assert response.data.content =~ "I couldn't post in this channel"
      assert Screens.get_stream_channel("1") == nil
    end

    test "edits the streams channel's message as rooms go live and end", %{room: room} do
      {:ok, _stream_channel} = Screens.put_stream_channel("1", "5", "30")
      restart_announcer()

      assert_called(Nostrum.Api.request(:patch, "/channels/5/messages/30", idle))
      assert idle.content =~ "Nobody is sharing their screen right now"

      Screens.broadcast(room, :live)
      :sys.get_state(Announcer)

      assert_called(Nostrum.Api.request(:patch, "/channels/5/messages/30", live))
      assert live.content =~ "🔴 **Elden Ring** by <@3>"
      assert live.allowed_mentions == %{parse: []}
      refute_called(Nostrum.Api.request(:post, "/channels/2/messages", _body))

      Screens.broadcast(%{room | title: "Boss fight"}, :updated)
      :sys.get_state(Announcer)
      assert_called(Nostrum.Api.request(:patch, "/channels/5/messages/30", renamed))
      assert renamed.content =~ "**Boss fight**"

      Screens.broadcast(room, :ended)
      :sys.get_state(Announcer)
      assert ended = List.last(status_edits())
      assert ended.content =~ "Nobody is sharing their screen right now"
    end

    test "posts the streams channel's message again when it was deleted", %{room: room} do
      {:ok, _stream_channel} = Screens.put_stream_channel("1", "5", "30")

      patch(
        Nostrum.Api,
        :request,
        callable(
          fn
            [:patch, "/channels/5/messages/30", _body] ->
              {:error,
               %ApiError{status_code: 404, response: %{code: 10_008, message: "Unknown Message"}}}

            [:post, "/channels/5/messages", _body] ->
              {:ok, ~s({"id": "40", "channel_id": "5"})}

            request ->
              discord(request)
          end,
          dispatch: :list
        )
      )

      restart_announcer()
      Screens.broadcast(room, :live)
      :sys.get_state(Announcer)

      assert_called(Nostrum.Api.request(:post, "/channels/5/messages", _body))
      assert %{discord_message_id: "40"} = Screens.get_stream_channel("1")

      # Stopping reposts the message too, so it needs the test's database connection
      stop_supervised!(Announcer)
    end

    test "marks the streams channel's name while anyone is sharing", %{room: room} do
      {:ok, _stream_channel} = Screens.put_stream_channel("1", "5", "30")
      name = stub_channel_name()
      restart_announcer()
      other = %{room | id: "other", owner_id: "4"}

      Screens.broadcast(room, :live)
      wait_for_renames()
      assert Agent.get(name, & &1) == "🔴-streams"

      # Only the first screen share going live and the last one ending rename it
      Screens.broadcast(other, :live)
      Screens.broadcast(room, :ended)
      wait_for_renames()
      assert length(renames()) == 1

      Screens.broadcast(other, :ended)
      wait_for_renames()
      assert Agent.get(name, & &1) == "streams"
      assert length(renames()) == 2
    end

    test "waits for Discord's rate limit to rename the channel again", %{room: room} do
      {:ok, _stream_channel} = Screens.put_stream_channel("1", "5", "30")
      name = stub_channel_name()
      restart_announcer()

      for event <- [:live, :ended, :live] do
        Screens.broadcast(room, event)
        wait_for_renames()
      end

      assert length(renames()) == 2
      assert Agent.get(name, & &1) == "streams"
      assert :sys.get_state(Announcer).guilds["1"].rename_timer

      # Nothing to rename once the timer fires, as the screen share ended meanwhile
      Screens.broadcast(room, :ended)
      send(Announcer, {:sync_name, "1"})
      wait_for_renames()
      assert length(renames()) == 2
    end

    # Answers like Discord, with the streams channel named "streams"
    defp discord([:get, "/channels/5"]), do: {:ok, ~s({"id": "5", "name": "streams", "type": 0})}
    defp discord(_request), do: {:ok, ~s({"id": "20", "channel_id": "2"})}

    # The streams channel keeps the name it's renamed to
    defp stub_channel_name do
      {:ok, name} = Agent.start_link(fn -> "streams" end)

      channel = fn -> {:ok, Jason.encode!(%{id: "5", name: Agent.get(name, & &1), type: 0})} end

      patch(
        Nostrum.Api,
        :request,
        callable(
          fn
            [:get, "/channels/5"] ->
              channel.()

            [%{method: :patch, route: "/channels/5", body: %{name: new_name}}] ->
              Agent.update(name, fn _name -> new_name end)
              channel.()

            request ->
              discord(request)
          end,
          dispatch: :list
        )
      )

      name
    end

    defp renames do
      for {:request, [%{method: :patch, route: "/channels/5"}]} <- history(Nostrum.Api),
          do: :renamed
    end

    # Renames run in tasks, which finish after the announcer handled the events
    defp wait_for_renames do
      if Enum.any?(:sys.get_state(Announcer).guilds, fn {_id, guild} -> guild.renaming end) do
        Process.sleep(10)
        wait_for_renames()
      end
    end

    defp status_edits do
      for {:request, [:patch, "/channels/5/messages/30", body]} <- history(Nostrum.Api), do: body
    end

    defp restart_announcer do
      stop_supervised!(Announcer)
      start_supervised!(Announcer)
      :sys.get_state(Announcer)
    end
  end
end
