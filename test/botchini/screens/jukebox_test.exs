defmodule BotchiniTest.Screens.JukeboxTest do
  use ExUnit.Case, async: false

  use Patch

  @moduletag :capture_log

  alias Botchini.Music.YtDlp
  alias Botchini.Screens.{Activity, Jukebox}

  @ana %{id: "10", name: "Ana"}

  # Every test gets a guild of its own. yt-dlp finds a song titled like the
  # search, three minutes long, and "downloads" a tiny file
  setup do
    guild_id = "jukebox-#{System.unique_integer([:positive])}"
    on_exit(fn -> Jukebox.stop(guild_id) end)

    patch(YtDlp, :lookup, fn
      "nothing" -> {:error, :not_found}
      "live" -> {:ok, video("live", nil)}
      "marathon" -> {:ok, video("marathon", :timer.hours(2))}
      term -> {:ok, video(term, :timer.minutes(3))}
    end)

    patch(YtDlp, :download, fn
      "https://youtu.be/broken", _dir, _name ->
        {:error, :unavailable}

      _url, dir, name ->
        path = Path.join(dir, "#{name}.m4a")
        File.write!(path, "audio")
        {:ok, path}
    end)

    %{guild_id: guild_id}
  end

  defp video(title, duration_ms) do
    %{
      id: "abcdefghijk",
      title: title,
      url: "https://youtu.be/#{title}",
      thumbnail: "https://i.ytimg.com/vi/abcdefghijk/mqdefault.jpg",
      duration_ms: duration_ms,
      channel: "Channel"
    }
  end

  defp add(guild_id, terms),
    do: Enum.each(List.wrap(terms), &(:ok = Jukebox.add(guild_id, &1, @ana)))

  defp titles(%{queue: queue}), do: Enum.map(queue, & &1.title)

  defp current_title(%{current: nil}), do: nil
  defp current_title(%{current: current}), do: current.title

  # Songs are looked up and downloaded in the background
  defp eventually(fun, attempts \\ 40) do
    fun.()
  rescue
    error in [ExUnit.AssertionError, MatchError] ->
      if attempts == 0 do
        reraise error, __STACKTRACE__
      else
        Process.sleep(25)
        eventually(fun, attempts - 1)
      end
  end

  defp playing(guild_id, title) do
    eventually(fn ->
      state = Jukebox.state(guild_id)
      assert current_title(state) == title
      assert state.playing?
      state
    end)
  end

  test "has nothing playing before a song is added", %{guild_id: guild_id} do
    assert %{current: nil, queue: [], playing?: false, previous?: false} = Jukebox.state(guild_id)
    assert Jukebox.toggle(guild_id) == :ok
    assert Jukebox.file(guild_id, "anything") == :error
  end

  test "plays the first song added, and queues the others in order", %{guild_id: guild_id} do
    Jukebox.subscribe(guild_id)
    add(guild_id, ["one", "two", "three"])

    state = playing(guild_id, "one")

    assert titles(state) == ["two", "three"]
    assert %{added_by: "Ana", duration_ms: 180_000, url: "https://youtu.be/one"} = state.current
    refute Map.has_key?(state.current, :file)
    assert_receive {:music, {:state, %{current: %{title: "one"}}}}
  end

  test "tells everyone who added a song, once it's found", %{guild_id: guild_id} do
    add(guild_id, "one")

    eventually(fn -> assert [_added] = Activity.list(guild_id) end)
    assert [%{kind: :song_added, actor: "Ana", detail: "one"}] = Activity.list(guild_id)
  end

  test "tells who added a song when nothing is found", %{guild_id: guild_id} do
    add(guild_id, ["one", "nothing", "live", "marathon"])

    assert_receive {:music, {:add_failed, "nothing", :not_found}}
    assert_receive {:music, {:add_failed, "live", :live}}
    assert_receive {:music, {:add_failed, "marathon", :too_long}}
    assert titles(playing(guild_id, "one")) == []
  end

  test "ignores blank songs and cleans up the search", %{guild_id: guild_id} do
    assert Jukebox.add(guild_id, "  \n ", @ana) == {:error, :blank}

    add(guild_id, "  never\ngonna  ")

    playing(guild_id, "never gonna")
  end

  test "keeps the queue from growing forever", %{guild_id: guild_id} do
    add(guild_id, "playing")
    playing(guild_id, "playing")
    add(guild_id, Enum.map(1..50, &"song #{&1}"))

    assert Jukebox.add(guild_id, "one too many", @ana) == {:error, :full}
  end

  test "pauses and plays again, keeping the spot", %{guild_id: guild_id} do
    add(guild_id, "one")
    playing(guild_id, "one")

    Jukebox.toggle(guild_id)
    paused = Jukebox.state(guild_id)
    Process.sleep(20)

    assert %{paused?: true, playing?: false} = paused
    assert Jukebox.state(guild_id).position_ms == paused.position_ms

    Jukebox.toggle(guild_id)
    Process.sleep(20)

    assert %{paused?: false, playing?: true, position_ms: position} = Jukebox.state(guild_id)
    assert position > paused.position_ms
  end

  test "skips to the next song, telling everyone who skipped", %{guild_id: guild_id} do
    add(guild_id, ["one", "two"])
    playing(guild_id, "one")

    Jukebox.next(guild_id, "Bia")

    assert titles(playing(guild_id, "two")) == []
    assert %{kind: :song_skipped, actor: "Bia", detail: "one"} = hd(Activity.list(guild_id))

    Jukebox.next(guild_id, "Bia")

    assert %{current: nil, playing?: false, previous?: true} = Jukebox.state(guild_id)
  end

  test "moves on when a song ends", %{guild_id: guild_id} do
    add(guild_id, ["one", "two"])
    %{current: %{id: id}} = playing(guild_id, "one")

    pid = GenServer.whereis({:via, Registry, {Botchini.Screens.JukeboxRegistry, guild_id}})
    send(pid, {:ended, "an older song"})
    assert current_title(Jukebox.state(guild_id)) == "one"

    send(pid, {:ended, id})

    playing(guild_id, "two")
    refute Enum.any?(Activity.list(guild_id), &(&1.kind == :song_skipped))
  end

  test "goes back to the song before, which plays next again", %{guild_id: guild_id} do
    add(guild_id, ["one", "two", "three"])
    playing(guild_id, "one")
    Jukebox.next(guild_id, "Ana")
    playing(guild_id, "two")

    Jukebox.previous(guild_id)

    assert titles(playing(guild_id, "one")) == ["two", "three"]

    # With nothing before it, the song starts over
    Jukebox.toggle(guild_id)
    Jukebox.previous(guild_id)

    assert %{position_ms: position, paused?: false} = playing(guild_id, "one")
    assert position < 1_000
  end

  test "lets songs be removed from the queue", %{guild_id: guild_id} do
    add(guild_id, ["one", "two", "three"])
    %{queue: [two, _three]} = playing(guild_id, "one")

    Jukebox.remove(guild_id, two.id)
    Jukebox.remove(guild_id, "not in the queue")

    assert titles(Jukebox.state(guild_id)) == ["three"]
    assert Jukebox.file(guild_id, two.id) == :error
  end

  test "skips songs that can't be downloaded", %{guild_id: guild_id} do
    add(guild_id, ["broken", "two"])

    playing(guild_id, "two")

    assert Enum.any?(
             Activity.list(guild_id),
             &match?(%{kind: :song_failed, detail: "broken"}, &1)
           )
  end

  test "tries downloading again once when YouTube refuses it", %{guild_id: guild_id} do
    attempts = :counters.new(1, [])

    patch(YtDlp, :download, fn _url, dir, name ->
      :counters.add(attempts, 1, 1)

      if :counters.get(attempts, 1) == 1 do
        {:error, :forbidden}
      else
        path = Path.join(dir, "#{name}.m4a")
        File.write!(path, "audio")
        {:ok, path}
      end
    end)

    add(guild_id, "one")

    playing(guild_id, "one")
    assert :counters.get(attempts, 1) == 2
  end

  test "only keeps the files of the songs around the one playing", %{guild_id: guild_id} do
    add(guild_id, ["one", "two", "three", "four"])
    %{current: one, queue: [two, three, _four]} = playing(guild_id, "one")

    eventually(fn -> assert {:ok, _path} = Jukebox.file(guild_id, two.id) end)
    assert {:ok, one_path} = Jukebox.file(guild_id, one.id)
    assert File.read!(one_path) == "audio"
    assert Jukebox.file(guild_id, three.id) == :error

    Jukebox.next(guild_id, "Ana")
    Jukebox.next(guild_id, "Ana")
    playing(guild_id, "three")

    assert Jukebox.file(guild_id, one.id) == :error
    refute File.exists?(one_path)
    assert {:ok, _path} = Jukebox.file(guild_id, two.id)
  end

  test "keeps each guild's music apart", %{guild_id: guild_id} do
    add(guild_id, "one")
    playing(guild_id, "one")

    assert %{current: nil} = Jukebox.state("#{guild_id}-other")
  end
end
