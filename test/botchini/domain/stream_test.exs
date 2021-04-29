defmodule BotchiniTest.Domain.StreamTest do
  use ExUnit.Case, async: false

  import Mock

  alias Botchini.{Domain, Repo, Twitch}
  alias Botchini.Schema.{Guild, Stream, StreamFollower}
  alias Ecto.Adapters.SQL

  setup do
    :ok = SQL.Sandbox.checkout(Repo)
  end

  describe "follow" do
    test "create stream, guild and follower, calls twitch API" do
      twitch_id = Faker.String.base64()
      twitch_sub_id = Faker.String.base64()

      code = String.downcase(Faker.String.base64())

      message = %{
        guild_id: Faker.String.base64(),
        channel_id: Faker.String.base64(),
        user_id: Faker.String.base64()
      }

      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => twitch_id} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => twitch_sub_id} end do
        {:ok, stream} = Domain.Stream.follow(code, message)

        assert_called(Twitch.API.get_user(code))
        assert_called(Twitch.API.add_stream_webhook(twitch_id))

        assert stream != nil
        assert stream.code == code
        assert stream.twitch_user_id == twitch_id
        assert stream.twitch_subscription_id == twitch_sub_id

        guild = Repo.get_by!(Guild, discord_guild_id: message.guild_id)
        follower = Repo.get_by!(StreamFollower, stream_id: stream.id)

        assert follower.guild_id == guild.id
        assert follower.discord_channel_id == message.channel_id
        assert follower.discord_user_id == message.user_id
      end
    end

    test "should cleanup stream code before inserting" do
      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => Faker.String.base64()} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => Faker.String.base64()} end do
        message = %{
          guild_id: Faker.String.base64(),
          channel_id: Faker.String.base64(),
          user_id: Faker.String.base64()
        }

        {:ok, stream} = Domain.Stream.follow(" TestWithSpaceAndUppercase ", message)

        assert stream != nil
        assert stream.code == "testwithspaceanduppercase"
      end
    end

    test "use existing stream" do
      stream =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      message = %{
        guild_id: Faker.String.base64(),
        channel_id: Faker.String.base64(),
        user_id: Faker.String.base64()
      }

      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => stream.twitch_user_id} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => stream.twitch_subscription_id} end do
        {:ok, returned_stream} = Domain.Stream.follow(stream.code, message)
        assert stream.id == returned_stream.id

        assert_not_called(Twitch.API.get_user(:_))
        assert_not_called(Twitch.API.add_stream_webhook(:_))

        assert Repo.get_by(Guild, discord_guild_id: message.guild_id)
        assert Repo.get_by(StreamFollower, stream_id: stream.id)
      end
    end

    test "use existing guild" do
      guild = Guild.insert(%Guild{discord_guild_id: Faker.String.base64()})

      message = %{
        guild_id: guild.discord_guild_id,
        channel_id: Faker.String.base64(),
        user_id: Faker.String.base64()
      }

      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => Faker.String.base64()} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => Faker.String.base64()} end do
        assert {:ok, stream} =
                 Domain.Stream.follow(String.downcase(Faker.String.base64()), message)

        follower = Repo.get_by!(StreamFollower, stream_id: stream.id)
        assert follower.guild_id == guild.id
      end
    end

    test "invalid_stream if twitch API returns nil" do
      with_mock Twitch.API,
        get_user: fn _code -> nil end,
        add_stream_webhook: fn _twitch_id -> %{"id" => Faker.String.base64()} end do
        response =
          Domain.Stream.follow(String.downcase(Faker.String.base64()), %{
            guild_id: Faker.String.base64(),
            channel_id: Faker.String.base64(),
            user_id: Faker.String.base64()
          })

        assert response == {:error, :invalid_stream}
        assert_not_called(Twitch.API.add_stream_webhook(:_))
      end
    end

    test "already_following if channel was already following" do
      stream =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      guild = Guild.insert(%Guild{discord_guild_id: Faker.String.base64()})

      follower =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream.id,
          guild_id: guild.id
        })

      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => stream.twitch_user_id} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => stream.twitch_subscription_id} end do
        message = %{
          guild_id: guild.discord_guild_id,
          channel_id: follower.discord_channel_id,
          user_id: follower.discord_user_id
        }

        assert {:error, :already_following} = Domain.Stream.follow(stream.code, message)
      end
    end
  end

  describe "stop_following" do
    test "stop following, and delete stream if no more followers for that stream" do
      stream =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      guild = Guild.insert(%Guild{discord_guild_id: Faker.String.base64()})

      follow =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream.id,
          guild_id: guild.id
        })

      with_mock Twitch.API,
        delete_stream_webhook: fn _ -> :noop end do
        assert {:ok} = Domain.Stream.stop_following(stream.code, follow.discord_channel_id)

        assert_called(Twitch.API.delete_stream_webhook(stream.twitch_subscription_id))

        refute Repo.get_by(StreamFollower, id: follow.id)
        refute Repo.get_by(Stream, id: stream.id)
      end
    end

    test "stop following, but DONT delete stream if still has followers" do
      stream =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      guild = Guild.insert(%Guild{discord_guild_id: Faker.String.base64()})

      follow_1 =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream.id,
          guild_id: guild.id
        })

      follow_2 =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream.id,
          guild_id: guild.id
        })

      with_mock Twitch.API,
        delete_stream_webhook: fn _ -> :noop end do
        assert {:ok} = Domain.Stream.stop_following(stream.code, follow_1.discord_channel_id)

        assert_not_called(Twitch.API.delete_stream_webhook(:_))

        refute Repo.get_by(StreamFollower, id: follow_1.id)
        assert Repo.get_by(StreamFollower, id: follow_2.id)
        assert Repo.get_by(Stream, id: stream.id)
      end
    end

    test "not_found if stream was not found" do
      stream =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      guild = Guild.insert(%Guild{discord_guild_id: Faker.String.base64()})

      follow =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream.id,
          guild_id: guild.id
        })

      with_mock Twitch.API,
        delete_stream_webhook: fn _ -> :noop end do
        assert {:error, :not_found} =
                 Domain.Stream.stop_following(Faker.String.base64(), follow.discord_channel_id)

        assert_not_called(Twitch.API.delete_stream_webhook(:_))

        assert Repo.get_by(StreamFollower, id: follow.id)
        assert Repo.get_by(Stream, id: stream.id)
      end
    end

    test "not_found if follower was not found" do
      stream =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      with_mock Twitch.API,
        delete_stream_webhook: fn _ -> :noop end do
        assert {:error, :not_found} =
                 Domain.Stream.stop_following(stream.code, Faker.String.base64())

        assert_not_called(Twitch.API.delete_stream_webhook(:_))

        assert Repo.get_by(Stream, id: stream.id)
      end
    end
  end

  describe "following_list" do
    test "lists all follower.channel_id and stream.code for a guild" do
      stream_1 =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      stream_2 =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      guild = Guild.insert(%Guild{discord_guild_id: Faker.String.base64()})

      follow_1 =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream_1.id,
          guild_id: guild.id
        })

      follow_2 =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream_2.id,
          guild_id: guild.id
        })

      {:ok, following_list} = Domain.Stream.following_list(guild.discord_guild_id)

      assert length(following_list) == 2
      assert Enum.at(following_list, 0) == {follow_1.discord_channel_id, stream_1.code}
      assert Enum.at(following_list, 1) == {follow_2.discord_channel_id, stream_2.code}
    end

    test "lists all followers for same stream" do
      stream =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      guild = Guild.insert(%Guild{discord_guild_id: Faker.String.base64()})

      follow_1 =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream.id,
          guild_id: guild.id
        })

      follow_2 =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream.id,
          guild_id: guild.id
        })

      {:ok, following_list} = Domain.Stream.following_list(guild.discord_guild_id)

      assert length(following_list) == 2
      assert Enum.at(following_list, 0) == {follow_1.discord_channel_id, stream.code}
      assert Enum.at(following_list, 1) == {follow_2.discord_channel_id, stream.code}
    end

    test "ignores followers from other guild" do
      stream =
        Stream.insert(%Stream{
          code: String.downcase(Faker.String.base64()),
          twitch_user_id: Faker.String.base64(),
          twitch_subscription_id: Faker.String.base64()
        })

      guild = Guild.insert(%Guild{discord_guild_id: Faker.String.base64()})
      other_guild = Guild.insert(%Guild{discord_guild_id: Faker.String.base64()})

      follow_1 =
        StreamFollower.insert(%StreamFollower{
          discord_channel_id: Faker.String.base64(),
          discord_user_id: Faker.String.base64(),
          stream_id: stream.id,
          guild_id: guild.id
        })

      StreamFollower.insert(%StreamFollower{
        discord_channel_id: Faker.String.base64(),
        discord_user_id: Faker.String.base64(),
        stream_id: stream.id,
        guild_id: other_guild.id
      })

      {:ok, following_list} = Domain.Stream.following_list(guild.discord_guild_id)

      assert length(following_list) == 1
      assert Enum.at(following_list, 0) == {follow_1.discord_channel_id, stream.code}
    end
  end
end
