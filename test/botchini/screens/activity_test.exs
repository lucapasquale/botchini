defmodule BotchiniTest.Screens.ActivityTest do
  use ExUnit.Case, async: false

  alias Botchini.Screens.Activity

  # Every test gets a guild of its own, as the activity is shared by the whole app
  setup do
    %{guild_id: "activity-#{System.unique_integer([:positive])}"}
  end

  defp meta(name), do: %{name: name, admin?: false}

  # What Presence reports when its `handle_metas/4` callback is called
  defp diff(joins, leaves) do
    %{
      joins: Map.new(joins, fn {id, name} -> {id, %{metas: [meta(name)]}} end),
      leaves: Map.new(leaves, fn {id, name} -> {id, %{metas: [meta(name)]}} end)
    }
  end

  defp present(users), do: Map.new(users, fn {id, name} -> {id, [meta(name)]} end)

  defp kinds(guild_id), do: guild_id |> Activity.list() |> Enum.map(&{&1.kind, &1.actor})

  describe "say/3" do
    @ana %{id: "10", name: "Ana"}

    test "adds the message, saying who wrote it", %{guild_id: guild_id} do
      Activity.subscribe(guild_id)

      assert Activity.say(guild_id, @ana, "gg") == :ok

      assert_receive {:screen_activity,
                      %{kind: :message, actor: "Ana", actor_id: "10", detail: "gg"}}

      assert [%{kind: :message, detail: "gg"}] = Activity.list(guild_id)
    end

    test "drops blank messages", %{guild_id: guild_id} do
      assert Activity.say(guild_id, @ana, "  \n ") == :blank
      assert Activity.list(guild_id) == []
    end

    test "keeps messages on one line, and cuts long ones", %{guild_id: guild_id} do
      Activity.say(guild_id, @ana, " one\ntwo\t ")
      Activity.say(guild_id, @ana, String.duplicate("a", 400))

      assert [%{detail: long}, %{detail: "one two"}] = Activity.list(guild_id)
      assert String.length(long) == Activity.max_message_length()
    end

    test "other events don't say who did them", %{guild_id: guild_id} do
      Activity.record(guild_id, :sound_stopped, "Ana")

      assert [%{actor_id: nil}] = Activity.list(guild_id)
    end
  end

  describe "hit/2" do
    test "lets members send a few messages in a row, then makes them wait" do
      limiter =
        Enum.reduce(1..5, Activity.new_limiter(), fn second, limiter ->
          assert {:ok, limiter} = Activity.hit(limiter, second * 100)
          limiter
        end)

      assert Activity.hit(limiter, 600) == :limited
      # The first message is out of the window 10 seconds after it was sent
      assert {:ok, _limiter} = Activity.hit(limiter, 10_100)
    end
  end

  describe "record/4" do
    test "lists the latest events first", %{guild_id: guild_id} do
      assert Activity.list(guild_id) == []

      Activity.record(guild_id, :sound, "Ana", "🐻 Volibero")
      Activity.record(guild_id, :stream_started, "Luca")

      assert [
               %{kind: :stream_started, actor: "Luca", detail: nil},
               %{kind: :sound, actor: "Ana", detail: "🐻 Volibero", at: %DateTime{}}
             ] = Activity.list(guild_id)
    end

    test "keeps the guilds apart", %{guild_id: guild_id} do
      Activity.record(guild_id, :sound, "Ana", "🐻 Volibero")

      assert Activity.list("#{guild_id}-other") == []
    end

    test "only keeps the latest events", %{guild_id: guild_id} do
      for number <- 1..120, do: Activity.record(guild_id, :joined, "User #{number}")

      events = Activity.list(guild_id)

      assert length(events) == 100
      assert hd(events).actor == "User 120"
      assert List.last(events).actor == "User 21"
    end

    test "tells the subscribers", %{guild_id: guild_id} do
      Activity.subscribe(guild_id)

      Activity.record(guild_id, :sound_stopped, "Ana")

      assert_receive {:screen_activity, %{kind: :sound_stopped, actor: "Ana"}}
    end
  end

  describe "presence_changed/3" do
    test "reports who joined", %{guild_id: guild_id} do
      Activity.presence_changed(guild_id, diff([{"1", "Ana"}], []), present([{"1", "Ana"}]))

      assert kinds(guild_id) == [joined: "Ana"]
    end

    test "doesn't report more tabs of someone who is online", %{guild_id: guild_id} do
      # The second tab is the only join of the diff, but they have two now
      presences = %{"1" => [meta("Ana"), meta("Ana")]}
      Activity.presence_changed(guild_id, diff([{"1", "Ana"}], []), presences)

      assert kinds(guild_id) == []
    end

    test "reports who left once the grace period passed", %{guild_id: guild_id} do
      Activity.subscribe(guild_id)
      Activity.presence_changed(guild_id, diff([], [{"1", "Ana"}]), %{})

      assert kinds(guild_id) == []
      assert_receive {:screen_activity, %{kind: :left, actor: "Ana"}}, 1_000
      assert kinds(guild_id) == [left: "Ana"]
    end

    test "doesn't report leaving tabs of someone who is still online", %{guild_id: guild_id} do
      Activity.subscribe(guild_id)
      Activity.presence_changed(guild_id, diff([], [{"1", "Ana"}]), present([{"1", "Ana"}]))

      refute_receive {:screen_activity, _event}, 300
      assert kinds(guild_id) == []
    end

    test "doesn't report reloads and page changes as leaving", %{guild_id: guild_id} do
      Activity.subscribe(guild_id)
      Activity.presence_changed(guild_id, diff([], [{"1", "Ana"}]), %{})
      Activity.presence_changed(guild_id, diff([{"1", "Ana"}], []), present([{"1", "Ana"}]))

      refute_receive {:screen_activity, _event}, 300
      assert kinds(guild_id) == []
    end

    test "reports leaving again after coming back and going", %{guild_id: guild_id} do
      Activity.subscribe(guild_id)
      Activity.presence_changed(guild_id, diff([], [{"1", "Ana"}]), %{})
      Activity.presence_changed(guild_id, diff([{"1", "Ana"}], []), present([{"1", "Ana"}]))
      Activity.presence_changed(guild_id, diff([], [{"1", "Ana"}]), %{})

      assert_receive {:screen_activity, %{kind: :left, actor: "Ana"}}, 1_000
      assert kinds(guild_id) == [left: "Ana"]
    end
  end
end
