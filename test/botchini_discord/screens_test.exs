defmodule BotchiniDiscordTest.ScreensTest do
  use ExUnit.Case, async: false

  use Patch

  @moduletag :capture_log

  alias Ecto.Adapters.SQL.Sandbox
  alias Nostrum.Error.ApiError
  alias Nostrum.Struct.{Guild.Member, Interaction, User}

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias BotchiniDiscord.Screens.Announcer
  alias BotchiniDiscord.Screens.Interactions.Screen

  setup do
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
    test "privately sends the broadcast and watch links" do
      response = Screen.handle_interaction(interaction(), subcommand("start"))

      assert response.data.flags == 64
      assert response.data.content =~ "**Luca's screen**"

      room = Screens.find_owner_room("1", "3")
      assert %Room{title: "Luca's screen", channel_id: "2", owner_name: "Luca"} = room

      assert [broadcast, watch] = buttons(response)
      assert broadcast.url =~ ~r"/screens/#{room.id}/broadcast##{room.broadcast_key}$"
      assert watch.url =~ ~r"/screens/#{room.id}$"
      refute watch.url =~ room.broadcast_key
    end

    test "sends the running room's links again" do
      first = Screen.handle_interaction(interaction(), subcommand("start"))
      response = Screen.handle_interaction(interaction(), subcommand("start"))

      assert buttons(response) == buttons(first)
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
    :ok = Sandbox.checkout(Botchini.Repo)

    response = Screen.handle_interaction(interaction(), subcommand("obs"))

    assert response.data.flags == 64
    assert response.data.content =~ "/api/whip`"
    assert [_match, key] = Regex.run(~r/\|\|`(.+)`\|\|/, response.data.content)
    assert %{discord_user_id: "3", discord_channel_id: "2"} = Screens.get_stream_key(key)
  end

  test "/stream list only shows rooms that are live" do
    Screen.handle_interaction(interaction(), subcommand("start"))
    response = Screen.handle_interaction(interaction(), subcommand("list"))

    assert response.data.content =~ "Nobody is sharing their screen right now"
    assert [%{label: "Watch all", url: url}] = buttons(response)
    assert url =~ ~r"/screens#.+$"
  end

  test "/stream list links to every live room and to all of them" do
    Screen.handle_interaction(interaction(), subcommand("start"))
    room = Screens.find_owner_room("1", "3")
    patch(Screens, :list_rooms, [%{room | live?: true}])

    response = Screen.handle_interaction(interaction(), subcommand("list"))

    assert response.data.content =~ "**Luca's screen** by <@3>"
    assert [watch, watch_all] = buttons(response)
    assert watch.url =~ ~r"/screens/#{room.id}$"
    assert watch_all.label == "Watch all"
  end

  test "can only be used inside a server" do
    response = Screen.handle_interaction(%{interaction() | member: nil}, subcommand("list"))

    assert response.data.content == "Can only be used inside a server!"
  end

  describe "Announcer" do
    setup do
      # Stubs the HTTP request instead of Message.create/2, so Nostrum still
      # prepares the payloads like it would for Discord
      patch(Nostrum.Api, :request, {:ok, ~s({"id": "20", "channel_id": "2"})})
      start_supervised!(Announcer)

      room = %Room{
        id: "room",
        broadcast_key: "key",
        title: "Elden Ring",
        guild_id: "1",
        channel_id: "2",
        owner_id: "3",
        owner_name: "Luca"
      }

      %{room: room}
    end

    test "posts the watch link once live, and marks it as ended", %{room: room} do
      Screens.broadcast(room, :live)
      Screens.broadcast(room, :ended)
      # Syncs with the announcer, so both events were handled
      :sys.get_state(Announcer)

      assert_called(Nostrum.Api.request(:post, "/channels/2/messages", live))
      assert live.content =~ "<@3> is sharing their screen: **Elden Ring**"
      assert live.allowed_mentions == %{parse: []}
      assert [%{components: [%{label: "Watch", url: url}]}] = live.components
      assert url =~ "/screens/room"

      assert_called(Nostrum.Api.request(:patch, "/channels/2/messages/20", ended))
      assert ended.content =~ "stopped sharing"
      assert ended.components == []
      assert ended.allowed_mentions == %{parse: []}
    end

    test "updates the live message when the title changes", %{room: room} do
      Screens.broadcast(room, :live)
      :sys.get_state(Announcer)
      Screens.broadcast(%{room | viewer_count: 2}, :updated)
      Screens.broadcast(%{room | title: "Boss *fight*"}, :updated)
      :sys.get_state(Announcer)

      assert_called_once(Nostrum.Api.request(:patch, "/channels/2/messages/20", edited))
      assert edited.content =~ "**Boss \\*fight\\***"
      assert [%{components: [%{label: "Watch"}]}] = edited.components
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
  end
end
