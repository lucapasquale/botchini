defmodule BotchiniTest.Twitch.TwitchTest do
  use Botchini.DataCase, async: false

  import Mock

  alias Botchini.{Repo, Twitch}
  alias Botchini.Twitch.Schema.{Follower, Stream}

  describe "follow" do
    test "create stream, guild and follower, calls twitch API" do
      twitch_id = Faker.String.base64()
      twitch_sub_id = Faker.String.base64()

      code = Faker.String.base64()
      guild = generate_guild()
      message = generate_message()

      with_mock Twitch.API,
        get_user: fn _code -> %{id: twitch_id} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => twitch_sub_id} end do
        {:ok, stream} = Twitch.follow_stream(code, guild, message)

        assert_called(Twitch.API.get_user(code))
        assert_called(Twitch.API.add_stream_webhook(twitch_id))

        assert stream != nil
        assert stream.code == code
        assert stream.twitch_user_id == twitch_id
        assert stream.twitch_subscription_id == twitch_sub_id

        follower = Repo.get_by!(Follower, stream_id: stream.id)
        assert follower.guild_id == guild.id
        assert follower.discord_user_id == message.user_id
        assert follower.discord_channel_id == message.channel_id
      end
    end

    test "use existing stream" do
      stream = generate_stream()
      guild = generate_guild()
      message = generate_message()

      with_mock Twitch.API,
        get_user: fn _code -> %{id: stream.twitch_user_id} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => stream.twitch_subscription_id} end do
        {:ok, returned_stream} = Twitch.follow_stream(stream.code, guild, message)
        assert stream.id == returned_stream.id

        assert_not_called(Twitch.API.get_user(:_))
        assert_not_called(Twitch.API.add_stream_webhook(:_))

        assert Repo.get_by(Follower, stream_id: stream.id)
      end
    end

    test "invalid_stream if twitch API returns nil" do
      guild = generate_guild()
      message = generate_message()

      with_mock Twitch.API,
        get_user: fn _code -> nil end,
        add_stream_webhook: fn _twitch_id -> %{"id" => Faker.String.base64()} end do
        {:error, :invalid_stream} = Twitch.follow_stream("invalid_stream", guild, message)

        assert_not_called(Twitch.API.add_stream_webhook(:_))
      end
    end

    test "already_following if channel was already following" do
      stream = generate_stream()
      guild = generate_guild()
      follower = generate_follower(%{stream_id: stream.id, guild_id: guild.id})

      with_mock Twitch.API,
        get_user: fn _code -> %{id: stream.twitch_user_id} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => stream.twitch_subscription_id} end do
        message = %{
          channel_id: follower.discord_channel_id,
          user_id: follower.discord_user_id
        }

        {:error, :already_following} = Twitch.follow_stream(stream.code, guild, message)
      end
    end

    defp generate_message,
      do: %{
        user_id: Faker.String.base64(),
        channel_id: Faker.String.base64()
      }
  end

  describe "unfollow" do
    test "stop following, and delete stream if no more followers for that stream" do
      stream = generate_stream()
      guild = generate_guild()
      follower = generate_follower(%{stream_id: stream.id, guild_id: guild.id})

      with_mock Twitch.API,
        delete_stream_webhook: fn _ -> :noop end do
        {:ok} = Twitch.unfollow(stream.code, %{channel_id: follower.discord_channel_id})

        assert_called(Twitch.API.delete_stream_webhook(stream.twitch_subscription_id))

        refute Repo.get_by(Follower, id: follower.id)
        refute Repo.get_by(Stream, id: stream.id)
      end
    end

    test "stop following, but DONT delete stream if still has followers" do
      stream = generate_stream()
      guild = generate_guild()

      follower_1 = generate_follower(%{stream_id: stream.id, guild_id: guild.id})
      follower_2 = generate_follower(%{stream_id: stream.id, guild_id: guild.id})

      with_mock Twitch.API,
        delete_stream_webhook: fn _ -> :noop end do
        {:ok} = Twitch.unfollow(stream.code, %{channel_id: follower_1.discord_channel_id})

        assert_not_called(Twitch.API.delete_stream_webhook(:_))

        refute Repo.get_by(Follower, id: follower_1.id)
        assert Repo.get_by(Follower, id: follower_2.id)
        assert Repo.get_by(Stream, id: stream.id)
      end
    end

    test "not_found if stream was not found" do
      stream = generate_stream()
      guild = generate_guild()
      follower = generate_follower(%{stream_id: stream.id, guild_id: guild.id})

      with_mock Twitch.API,
        delete_stream_webhook: fn _ -> :noop end do
        {:error, :not_found} =
          Twitch.unfollow("invalid_stream", %{channel_id: follower.discord_channel_id})

        assert_not_called(Twitch.API.delete_stream_webhook(:_))

        assert Repo.get_by(Follower, id: follower.id)
        assert Repo.get_by(Stream, id: stream.id)
      end
    end

    test "not_found if follower was not found" do
      stream = generate_stream()

      with_mock Twitch.API,
        delete_stream_webhook: fn _ -> :noop end do
        {:error, :not_found} = Twitch.unfollow(stream.code, %{channel_id: "invalid_channel_id"})

        assert_not_called(Twitch.API.delete_stream_webhook(:_))

        assert Repo.get_by(Stream, id: stream.id)
      end
    end
  end

  describe "following_list" do
    test "lists all follower.channel_id and stream.code for a guild" do
      stream_1 = generate_stream()
      stream_2 = generate_stream()

      guild = generate_guild()

      follower_1 = generate_follower(%{stream_id: stream_1.id, guild_id: guild.id})
      follower_2 = generate_follower(%{stream_id: stream_2.id, guild_id: guild.id})

      {:ok, following_list} = Twitch.guild_following_list(guild)

      assert length(following_list) == 2
      assert Enum.at(following_list, 0) == {follower_1.discord_channel_id, stream_1.code}
      assert Enum.at(following_list, 1) == {follower_2.discord_channel_id, stream_2.code}
    end

    test "lists for same stream but different followers" do
      stream = generate_stream()
      guild = generate_guild()

      follower_1 = generate_follower(%{stream_id: stream.id, guild_id: guild.id})
      follower_2 = generate_follower(%{stream_id: stream.id, guild_id: guild.id})

      {:ok, following_list} = Twitch.guild_following_list(guild)

      assert length(following_list) == 2
      assert Enum.at(following_list, 0) == {follower_1.discord_channel_id, stream.code}
      assert Enum.at(following_list, 1) == {follower_2.discord_channel_id, stream.code}
    end

    test "ignores followers from other guild" do
      stream = generate_stream()
      guild = generate_guild()
      other_guild = generate_guild()

      follower_1 = generate_follower(%{stream_id: stream.id, guild_id: guild.id})
      generate_follower(%{stream_id: stream.id, guild_id: other_guild.id})

      {:ok, following_list} = Twitch.guild_following_list(guild)

      assert length(following_list) == 1
      assert Enum.at(following_list, 0) == {follower_1.discord_channel_id, stream.code}
    end
  end
end
