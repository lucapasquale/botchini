defmodule BotchiniTest.Domain.StreamTest do
  use ExUnit.Case, async: false

  import Mock

  alias Botchini.Domain
  alias Botchini.Repo
  alias Botchini.Schema.{Guild, Stream, StreamFollower}
  alias Botchini.Twitch

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "follow" do
    test "create stream, guild and follower, calls twitch API" do
      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => "twitch_id"} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => "twitch_sub_id"} end do
        {:ok, stream} =
          Domain.Stream.follow("test", %{
            guild_id: "guild_id",
            channel_id: "channel_id",
            user_id: "user_id"
          })

        assert stream != nil
        assert stream.code == "test"
        assert stream.twitch_user_id == "twitch_id"
        assert stream.twitch_subscription_id == "twitch_sub_id"

        guild = Repo.get_by!(Guild, discord_guild_id: "guild_id")
        follower = Repo.get_by!(StreamFollower, stream_id: stream.id)

        assert follower.guild_id == guild.id
        assert follower.discord_channel_id == "channel_id"
        assert follower.discord_user_id == "user_id"
      end
    end

    test "should cleanup stream code before inserting" do
      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => "twitch_id2"} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => "twitch_sub_id2"} end do
        {:ok, stream} =
          Domain.Stream.follow(" Test2 ", %{
            guild_id: "guild_id2",
            channel_id: "channel_id2",
            user_id: "user_id2"
          })

        assert stream != nil
        assert stream.code == "test2"
      end
    end

    test "use existing stream" do
      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => "twitch_id3"} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => "twitch_sub_id3"} end do
        stream =
          Stream.insert(%Stream{
            code: "test3",
            twitch_user_id: "twitch_id3",
            twitch_subscription_id: "twitch_sub_id3"
          })

        {:ok, returned_stream} =
          Domain.Stream.follow("test3", %{
            guild_id: "guild_id3",
            channel_id: "channel_id3",
            user_id: "user_id3"
          })

        assert stream.id == returned_stream.id

        assert_not_called(Twitch.API.get_user(:_))
        assert_not_called(Twitch.API.add_stream_webhook(:_))

        assert Repo.get_by!(Guild, discord_guild_id: "guild_id3")
        assert Repo.get_by!(StreamFollower, stream_id: stream.id)
      end
    end

    test "use existing guild" do
      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => "twitch_id4"} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => "twitch_sub_id4"} end do
        guild = Guild.insert(%Guild{discord_guild_id: "guild_id4"})

        {:ok, stream} =
          Domain.Stream.follow("test4", %{
            guild_id: "guild_id4",
            channel_id: "channel_id4",
            user_id: "user_id4"
          })

        assert stream

        follower = Repo.get_by!(StreamFollower, stream_id: stream.id)
        assert follower.guild_id == guild.id
      end
    end

    test "invalid_stream if twitch API returns nil" do
      with_mock Twitch.API,
        get_user: fn _code -> nil end,
        add_stream_webhook: fn _twitch_id -> %{"id" => "twitch_sub_id5"} end do
        assert {:error, :invalid_stream} ==
                 Domain.Stream.follow("test5", %{
                   guild_id: "guild_id5",
                   channel_id: "channel_id5",
                   user_id: "user_id5"
                 })

        assert_not_called(Twitch.API.add_stream_webhook(:_))
      end
    end

    test "already_following if channel already was following" do
      with_mock Twitch.API,
        get_user: fn _code -> %{"id" => "twitch_id6"} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => "twitch_sub_id6"} end do
        stream =
          Stream.insert(%Stream{
            code: "test6",
            twitch_user_id: "twitch_id6",
            twitch_subscription_id: "twitch_sub_id6"
          })

        guild = Guild.insert(%Guild{discord_guild_id: "guild_id6"})

        StreamFollower.insert(%StreamFollower{
          discord_channel_id: "channel_id6",
          discord_user_id: "user_id6",
          stream_id: stream.id,
          guild_id: guild.id
        })

        assert {:error, :already_following} ==
                 Domain.Stream.follow("test6", %{
                   guild_id: "guild_id6",
                   channel_id: "channel_id6",
                   user_id: "user_id6"
                 })
      end
    end
  end
end
