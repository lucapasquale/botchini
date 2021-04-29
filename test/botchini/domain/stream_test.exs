defmodule BotchiniTest.Domain.StreamTest do
  use ExUnit.Case, async: false

  import Mock

  alias Botchini.Domain
  alias Botchini.Repo
  alias Botchini.Schema.{Guild, Stream, StreamFollower}
  alias Botchini.Twitch

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
      message = %{
        guild_id: Faker.String.base64(),
        channel_id: Faker.String.base64(),
        user_id: Faker.String.base64()
      }

      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => Faker.String.base64()} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => Faker.String.base64()} end do
        {:ok, stream} = Domain.Stream.follow(" TestWithSpaceAndUppercase ", message)

        assert stream != nil
        assert stream.code == "testwithspaceanduppercase"
      end
    end

    test "use existing stream" do
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
        stream =
          Stream.insert(%Stream{
            code: code,
            twitch_user_id: twitch_id,
            twitch_subscription_id: twitch_sub_id
          })

        {:ok, returned_stream} = Domain.Stream.follow(code, message)
        assert stream.id == returned_stream.id

        assert_not_called(Twitch.API.get_user(:_))
        assert_not_called(Twitch.API.add_stream_webhook(:_))

        assert Repo.get_by!(Guild, discord_guild_id: message.guild_id)
        assert Repo.get_by!(StreamFollower, stream_id: stream.id)
      end
    end

    test "use existing guild" do
      message = %{
        guild_id: Faker.String.base64(),
        channel_id: Faker.String.base64(),
        user_id: Faker.String.base64()
      }

      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => Faker.String.base64()} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => Faker.String.base64()} end do
        guild = Guild.insert(%Guild{discord_guild_id: message.guild_id})

        {:ok, stream} = Domain.Stream.follow(String.downcase(Faker.String.base64()), message)
        assert stream

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
        stream =
          Stream.insert(%Stream{
            code: code,
            twitch_user_id: twitch_id,
            twitch_subscription_id: twitch_sub_id
          })

        guild = Guild.insert(%Guild{discord_guild_id: message.guild_id})

        StreamFollower.insert(%StreamFollower{
          discord_channel_id: message.channel_id,
          discord_user_id: message.user_id,
          stream_id: stream.id,
          guild_id: guild.id
        })

        assert {:error, :already_following} == Domain.Stream.follow(code, message)
      end
    end
  end
end
