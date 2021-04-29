defmodule BotchiniTest.Domain.StreamTest do
  use ExUnit.Case, async: false

  import Mock

  alias Botchini.Domain
  alias Botchini.Repo
  alias Botchini.Schema.{Guild, Stream, StreamFollower}

  @message_info %{guild_id: "1", channel_id: "2", user_id: "3"}

  setup do
    # Explicitly get a connection before each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "follow" do
    test "create stream, calls twitch API" do
      with_mock Botchini.Twitch.API,
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
      with_mock Botchini.Twitch.API,
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

    test "invalid_stream if twitch API returns nil" do
      with_mock Botchini.Twitch.API, get_user: fn _code -> nil end do
        assert Domain.Stream.follow("test", @message_info) == {:error, :invalid_stream}
      end
    end
  end
end
