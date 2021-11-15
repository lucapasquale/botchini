defmodule BotchiniTest.Twitch.TwitchTest do
  use Botchini.DataCase, async: false

  import Mock

  alias Botchini.{Repo, Twitch}
  alias Botchini.Twitch.Schema.{Follower, Stream}

  describe "find_stream_by_twitch_user_id" do
    test "find stream by its twitch_user_id" do
      stream = generate_stream(%{twitch_user_id: Faker.String.base64()})

      ^stream = Twitch.find_stream_by_twitch_user_id(stream.twitch_user_id)
    end

    test "return nil of not found" do
      nil = Twitch.find_stream_by_twitch_user_id(Faker.String.base64())
    end
  end

  describe "find_followers_for_stream" do
    test "find stream by its twitch_user_id" do
      stream = generate_stream()
      guild = generate_guild()

      follower_1 = generate_follower(%{stream_id: stream.id, guild_id: guild.id})
      follower_2 = generate_follower(%{stream_id: stream.id, guild_id: guild.id})

      following_list = Twitch.find_followers_for_stream(stream)

      assert length(following_list) == 2
      assert Enum.find(following_list, &(&1.id == follower_1.id))
      assert Enum.find(following_list, &(&1.id == follower_2.id))
    end

    test "find empty list if none found" do
      stream = generate_stream()

      [] = Twitch.find_followers_for_stream(stream)
    end
  end

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

    test "follow from DM" do
      stream = generate_stream()
      message = %{channel_id: Faker.String.base64(), user_id: nil}

      with_mock Twitch.API,
        get_user: fn _code -> %{id: stream.twitch_user_id} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => stream.twitch_subscription_id} end do
        {:ok, _stream} = Twitch.follow_stream(stream.code, nil, message)

        follower = Repo.get_by(Follower, stream_id: stream.id)
        assert follower.discord_user_id == nil
        assert follower.discord_channel_id == message.channel_id
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

  describe "guild_following_list" do
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

  describe "channel_following_list" do
    test "lists all follower.channel_id and stream.code for a guild" do
      stream_1 = generate_stream()
      stream_2 = generate_stream()

      discord_channel_id = Faker.String.base64()
      generate_follower(%{stream_id: stream_1.id, discord_channel_id: discord_channel_id})
      generate_follower(%{stream_id: stream_2.id, discord_channel_id: discord_channel_id})

      {:ok, following_list} = Twitch.channel_following_list(discord_channel_id)
      assert following_list == [stream_1.code, stream_2.code]
    end

    test "ignores followers from other channel" do
      stream = generate_stream()

      discord_channel_id = Faker.String.base64()
      generate_follower(%{stream_id: stream.id, discord_channel_id: discord_channel_id})
      generate_follower(%{stream_id: stream.id, discord_channel_id: Faker.String.base64()})

      {:ok, following_list} = Twitch.channel_following_list(discord_channel_id)
      assert following_list == [stream.code]
    end
  end

  describe "channel_follower" do
    test "find follower for stream code by channel_id" do
      stream = generate_stream()
      guild = generate_guild()

      follower = generate_follower(%{stream_id: stream.id, guild_id: guild.id})

      {:ok, ^follower} =
        Twitch.channel_follower(stream.code, %{
          channel_id: follower.discord_channel_id
        })
    end

    test "not_found if no stream by that code" do
      stream = generate_stream()
      guild = generate_guild()

      follower = generate_follower(%{stream_id: stream.id, guild_id: guild.id})

      {:error, :not_found} =
        Twitch.channel_follower(Faker.String.base64(), %{
          channel_id: follower.discord_channel_id
        })
    end

    test "not_found if no follower for that channel_id by that code" do
      stream = generate_stream()

      {:error, :not_found} =
        Twitch.channel_follower(stream.code, %{
          channel_id: Faker.String.base64()
        })
    end
  end
end
