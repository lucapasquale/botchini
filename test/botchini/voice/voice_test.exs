defmodule BotchiniTest.Voice.VoiceTest do
  use Botchini.DataCase, async: false

  alias Botchini.Voice
  alias Botchini.Voice.Schema.Track

  describe "get_current_track" do
    test "returns nil if no current track" do
      guild = generate_guild()

      nil = Voice.get_current_track(guild)
    end

    test "gets first track that is playing" do
      guild = generate_guild()
      track = generate_track(%{guild_id: guild.id, status: :playing})

      ^track = Voice.get_current_track(guild)
    end

    test "gets first track that is paused" do
      guild = generate_guild()
      track = generate_track(%{guild_id: guild.id, status: :paused})

      ^track = Voice.get_current_track(guild)
    end

    test "ignores :waiting or :done tracks" do
      guild = generate_guild()

      generate_track(%{guild_id: guild.id, status: :done})
      track = generate_track(%{guild_id: guild.id, status: :playing})
      generate_track(%{guild_id: guild.id, status: :waiting})

      ^track = Voice.get_current_track(guild)
    end

    test "ignores tracks from other guilds" do
      other_guild = generate_guild()
      generate_track(%{guild_id: other_guild.id, status: :playing})

      guild = generate_guild()
      track = generate_track(%{guild_id: guild.id, status: :playing})

      ^track = Voice.get_current_track(guild)
    end

    test "raises if more than one current track" do
      guild = generate_guild()
      generate_track(%{guild_id: guild.id, status: :paused})
      generate_track(%{guild_id: guild.id, status: :playing})

      assert_raise Ecto.MultipleResultsError, fn ->
        Voice.get_current_track(guild)
      end
    end
  end

  describe "insert_track" do
    test "inserts new track to queue" do
      guild = generate_guild()
      play_url = Faker.String.base64()

      {:ok, track} = Voice.insert_track(%{play_url: play_url}, guild)

      assert track != nil
      assert track.status == :waiting
      assert track.play_url == play_url
      assert track.guild_id == guild.id
    end
  end

  describe "start_next_track" do
    test "set current track as done and starts next in queue" do
      guild = generate_guild()

      cur_track = generate_track(%{guild_id: guild.id, status: :playing})
      next_track = generate_track(%{guild_id: guild.id, status: :waiting})

      {:ok, updated_next_track} = Voice.start_next_track(guild)

      assert updated_next_track.id == next_track.id

      assert Repo.get_by(Track, id: cur_track.id).status == :done
      assert Repo.get_by(Track, id: next_track.id).status == :playing
    end

    test "starts next track even if no current" do
      guild = generate_guild()
      next_track = generate_track(%{guild_id: guild.id, status: :waiting})

      {:ok, updated_next_track} = Voice.start_next_track(guild)

      assert updated_next_track.id == next_track.id
      assert Repo.get_by(Track, id: next_track.id).status == :playing
    end

    test "returns nil if no current track nor next track" do
      guild = generate_guild()

      {:ok, nil} = Voice.start_next_track(guild)
    end

    test "only updates current track if no next track" do
      guild = generate_guild()
      cur_track = generate_track(%{guild_id: guild.id, status: :playing})

      {:ok, nil} = Voice.start_next_track(guild)

      assert Repo.get_by(Track, id: cur_track.id).status == :done
    end
  end

  describe "pause" do
    test "pauses current track" do
      guild = generate_guild()
      track = generate_track(%{guild_id: guild.id, status: :playing})

      {:ok, paused_track} = Voice.pause(guild)

      assert paused_track.id == track.id
      assert paused_track.status == :paused
    end

    test "pauses even if already paused" do
      guild = generate_guild()
      track = generate_track(%{guild_id: guild.id, status: :paused})

      {:ok, ^track} = Voice.pause(guild)
    end

    test "returns nil if no current track playing" do
      guild = generate_guild()

      {:ok, nil} = Voice.pause(guild)
    end
  end

  describe "resume" do
    test "resumes current track" do
      guild = generate_guild()
      track = generate_track(%{guild_id: guild.id, status: :paused})

      {:ok, resumed_track} = Voice.resume(guild)

      assert resumed_track.id == track.id
      assert resumed_track.status == :playing
    end

    test "resumes even if already paused" do
      guild = generate_guild()
      track = generate_track(%{guild_id: guild.id, status: :playing})

      {:ok, ^track} = Voice.resume(guild)
    end

    test "returns nil if no current track playing" do
      guild = generate_guild()

      {:ok, nil} = Voice.resume(guild)
    end
  end

  describe "clear_queue" do
    test "set all unplayed tracks as done" do
      guild = generate_guild()

      playing_track = generate_track(%{guild_id: guild.id, status: :playing})
      waiting_track1 = generate_track(%{guild_id: guild.id, status: :waiting})
      waiting_track2 = generate_track(%{guild_id: guild.id, status: :waiting})

      {3, _} = Voice.clear_queue(guild)

      assert Repo.get_by(Track, id: playing_track.id).status == :done
      assert Repo.get_by(Track, id: waiting_track1.id).status == :done
      assert Repo.get_by(Track, id: waiting_track2.id).status == :done
    end

    test "existing done tracks are not altered" do
      guild = generate_guild()

      track = generate_track(%{guild_id: guild.id, status: :done})

      {0, _} = Voice.clear_queue(guild)

      assert Repo.get_by(Track, id: track.id) == track
    end
  end
end
