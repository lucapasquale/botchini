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
      for number <- 1..60, do: Activity.record(guild_id, :joined, "User #{number}")

      events = Activity.list(guild_id)

      assert length(events) == 50
      assert hd(events).actor == "User 60"
      assert List.last(events).actor == "User 11"
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
