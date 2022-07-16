defmodule BotchiniTest.Creators.CreatorsTest do
  use Botchini.DataCase, async: false

  import Mock

  alias Botchini.{Repo, Creators}
  alias Botchini.Creators.Clients.Twitch
  alias Botchini.Creators.Schema.{Creator, Follower}

  describe "find_creator_by_twitch_user_id" do
    test "find creator by its twitch_user_id" do
      creator =
        generate_creator(%{
          metadata: %{
            "user_id" => Faker.String.base64(),
            "subscription_id" => Faker.String.base64()
          }
        })

      ^creator = Creators.find_creator_by_twitch_user_id(creator.metadata["user_id"])
    end

    test "return nil of not found" do
      nil = Creators.find_creator_by_twitch_user_id(Faker.String.base64())
    end
  end

  describe "find_followers_for_creator" do
    test "find creator by its twitch_user_id" do
      creator = generate_creator()
      guild = generate_guild()

      follower_1 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})
      follower_2 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      following_list = Creators.find_followers_for_creator(creator)

      assert length(following_list) == 2
      assert Enum.find(following_list, &(&1.id == follower_1.id))
      assert Enum.find(following_list, &(&1.id == follower_2.id))
    end

    test "find empty list if none found" do
      creator = generate_creator()

      [] = Creators.find_followers_for_creator(creator)
    end
  end

  describe "search_following_creators" do
    test "should find followed creators by similar term" do
      channel_id = Faker.String.base64()

      creator_1 = generate_creator(%{code: "myTest1"})
      generate_follower(%{creator_id: creator_1.id, discord_channel_id: channel_id})

      creator_2 = generate_creator(%{code: "myTest2"})
      generate_follower(%{creator_id: creator_2.id, discord_channel_id: channel_id})

      response = Creators.search_following_creators("test", %{channel_id: channel_id})
      assert response == [creator_1, creator_2]
    end

    test "should return everything if term is empty string" do
      channel_id = Faker.String.base64()

      creator_1 = generate_creator(%{code: "qwer"})
      generate_follower(%{creator_id: creator_1.id, discord_channel_id: channel_id})

      creator_2 = generate_creator(%{code: "asdf"})
      generate_follower(%{creator_id: creator_2.id, discord_channel_id: channel_id})

      creator_3 = generate_creator(%{code: "zxcv"})
      generate_follower(%{creator_id: creator_3.id, discord_channel_id: channel_id})

      response = Creators.search_following_creators("", %{channel_id: channel_id})
      assert response == [creator_1, creator_2, creator_3]
    end

    test "should empty if term does not match" do
      channel_id = Faker.String.base64()

      creator = generate_creator(%{code: "qwer"})
      generate_follower(%{creator_id: creator.id, discord_channel_id: channel_id})

      response = Creators.search_following_creators("asdf", %{channel_id: channel_id})
      assert response == []
    end

    test "should empty if no creator in channel" do
      response = Creators.search_following_creators("test", %{channel_id: Faker.String.base64()})
      assert response == []
    end

    test "should ignore creator if term does not match" do
      channel_id = Faker.String.base64()

      creator = generate_creator(%{code: "valid"})
      generate_follower(%{creator_id: creator.id, discord_channel_id: channel_id})

      invalid_creator = generate_creator(%{code: "somethingElse"})
      generate_follower(%{creator_id: invalid_creator.id, discord_channel_id: channel_id})

      response = Creators.search_following_creators("valid", %{channel_id: channel_id})
      assert response == [creator]
    end

    test "should ignore creator if its from different channel_id" do
      channel_id = Faker.String.base64()

      creator = generate_creator(%{code: "myTest1"})
      generate_follower(%{creator_id: creator.id, discord_channel_id: channel_id})

      invalid_creator = generate_creator(%{code: "myTest2"})
      generate_follower(%{creator_id: invalid_creator.id})

      response = Creators.search_following_creators("test", %{channel_id: channel_id})
      assert response == [creator]
    end
  end

  describe "follow_creator" do
    test "create creator, guild and follower, calls twitch API" do
      twitch_id = Faker.String.base64()
      twitch_sub_id = Faker.String.base64()

      code = Faker.String.base64()
      name = Faker.String.base64()
      guild = generate_guild()
      message = generate_message()

      with_mock Twitch,
        get_user: fn _code -> %{id: twitch_id, display_name: name} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => twitch_sub_id} end do
        {:ok, creator} = Creators.follow_creator({:twitch, code}, guild, message)

        assert_called(Twitch.get_user(code))
        assert_called(Twitch.add_stream_webhook(twitch_id))

        assert creator != nil
        assert creator.code == code
        assert creator.name == name
        assert creator.metadata.user_id == twitch_id
        assert creator.metadata.subscription_id == twitch_sub_id

        follower = Repo.get_by!(Follower, creator_id: creator.id)
        assert follower.guild_id == guild.id
        assert follower.discord_user_id == message.user_id
        assert follower.discord_channel_id == message.channel_id
      end
    end

    test "use existing creator" do
      creator = generate_creator()
      guild = generate_guild()
      message = generate_message()

      with_mock Twitch,
        get_user: fn _code -> %{id: creator.twitch_user_id} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => creator.twitch_subscription_id} end do
        {:ok, returned_creator} = Creators.follow_creator({:twitch, creator.code}, guild, message)
        assert creator.id == returned_creator.id

        assert_not_called(Twitch.get_user(:_))
        assert_not_called(Twitch.add_stream_webhook(:_))

        assert Repo.get_by(Follower, creator_id: creator.id)
      end
    end

    test "follow from direct message" do
      creator = generate_creator()
      message = %{channel_id: Faker.String.base64(), user_id: nil}

      with_mock Twitch,
        get_user: fn _code -> %{id: creator.metadata["user_id"]} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => creator.metadata["subscription_id"]} end do
        {:ok, _creator} = Creators.follow_creator({:twitch, creator.code}, nil, message)

        follower = Repo.get_by(Follower, creator_id: creator.id)
        assert follower.discord_user_id == nil
        assert follower.discord_channel_id == message.channel_id
      end
    end

    test "invalid_creator if twitch API returns nil" do
      guild = generate_guild()
      message = generate_message()

      with_mock Twitch,
        get_user: fn _code -> nil end,
        add_stream_webhook: fn _twitch_id -> %{"id" => Faker.String.base64()} end do
        {:error, :invalid_creator} =
          Creators.follow_creator({:twitch, "invalid_creator"}, guild, message)

        assert_not_called(Twitch.add_stream_webhook(:_))
      end
    end

    test "already_following if channel was already following" do
      creator = generate_creator()
      guild = generate_guild()
      follower = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      with_mock Twitch,
        get_user: fn _code -> %{id: creator.metadata["user_id"]} end,
        add_stream_webhook: fn _twitch_id -> %{"id" => creator.metadata["subscription_id"]} end do
        message = %{
          channel_id: follower.discord_channel_id,
          user_id: follower.discord_user_id
        }

        {:error, :already_following} =
          Creators.follow_creator({:twitch, creator.code}, guild, message)
      end
    end

    defp generate_message,
      do: %{
        user_id: Faker.String.base64(),
        channel_id: Faker.String.base64()
      }
  end

  describe "unfollow" do
    test "stop following, and delete creator if no more followers for that creator" do
      creator = generate_creator()
      guild = generate_guild()
      follower = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      with_mock Twitch,
        delete_stream_webhook: fn _ -> :noop end do
        {:ok} =
          Creators.unfollow({creator.service, creator.code}, %{
            channel_id: follower.discord_channel_id
          })

        assert_called(Twitch.delete_stream_webhook(creator.metadata["subscription_id"]))

        refute Repo.get_by(Follower, id: follower.id)
        refute Repo.get_by(Creator, id: creator.id)
      end
    end

    test "stop following, but DONT delete creator if still has followers" do
      creator = generate_creator()
      guild = generate_guild()

      follower_1 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})
      follower_2 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      with_mock Twitch,
        delete_stream_webhook: fn _ -> :noop end do
        {:ok} =
          Creators.unfollow({creator.service, creator.code}, %{
            channel_id: follower_1.discord_channel_id
          })

        assert_not_called(Twitch.delete_stream_webhook(:_))

        refute Repo.get_by(Follower, id: follower_1.id)
        assert Repo.get_by(Follower, id: follower_2.id)
        assert Repo.get_by(Creator, id: creator.id)
      end
    end

    test "not_found if creator was not found" do
      creator = generate_creator()
      guild = generate_guild()
      follower = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      with_mock Twitch,
        delete_stream_webhook: fn _ -> :noop end do
        {:error, :not_found} =
          Creators.unfollow({:twitch, "invalid_creator"}, %{
            channel_id: follower.discord_channel_id
          })

        assert_not_called(Twitch.delete_stream_webhook(:_))

        assert Repo.get_by(Follower, id: follower.id)
        assert Repo.get_by(Creator, id: creator.id)
      end
    end

    test "not_found if follower was not found" do
      creator = generate_creator()

      with_mock Twitch,
        delete_stream_webhook: fn _ -> :noop end do
        {:error, :not_found} =
          Creators.unfollow({creator.service, creator.code}, %{channel_id: "invalid_channel_id"})

        assert_not_called(Twitch.delete_stream_webhook(:_))

        assert Repo.get_by(Creator, id: creator.id)
      end
    end
  end

  describe "guild_following_list" do
    test "lists all follower.channel_id and creator.code for a guild" do
      creator_1 = generate_creator()
      creator_2 = generate_creator()

      guild = generate_guild()

      follower_1 = generate_follower(%{creator_id: creator_1.id, guild_id: guild.id})
      follower_2 = generate_follower(%{creator_id: creator_2.id, guild_id: guild.id})

      {:ok, following_list} = Creators.guild_following_list(guild)

      assert length(following_list) == 2
      assert Enum.at(following_list, 0) == {follower_1.discord_channel_id, creator_1.code}
      assert Enum.at(following_list, 1) == {follower_2.discord_channel_id, creator_2.code}
    end

    test "lists for same creator but different followers" do
      creator = generate_creator()
      guild = generate_guild()

      follower_1 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})
      follower_2 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      {:ok, following_list} = Creators.guild_following_list(guild)

      assert length(following_list) == 2
      assert Enum.at(following_list, 0) == {follower_1.discord_channel_id, creator.code}
      assert Enum.at(following_list, 1) == {follower_2.discord_channel_id, creator.code}
    end

    test "ignores followers from other guild" do
      creator = generate_creator()
      guild = generate_guild()
      other_guild = generate_guild()

      follower_1 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})
      generate_follower(%{creator_id: creator.id, guild_id: other_guild.id})

      {:ok, following_list} = Creators.guild_following_list(guild)

      assert length(following_list) == 1
      assert Enum.at(following_list, 0) == {follower_1.discord_channel_id, creator.code}
    end
  end

  describe "channel_following_list" do
    test "lists all follower.channel_id and creator.code for a guild" do
      creator_1 = generate_creator()
      creator_2 = generate_creator()

      discord_channel_id = Faker.String.base64()
      generate_follower(%{creator_id: creator_1.id, discord_channel_id: discord_channel_id})
      generate_follower(%{creator_id: creator_2.id, discord_channel_id: discord_channel_id})

      {:ok, following_list} = Creators.channel_following_list(discord_channel_id)
      assert following_list == [creator_1.code, creator_2.code]
    end

    test "ignores followers from other channel" do
      creator = generate_creator()

      discord_channel_id = Faker.String.base64()
      generate_follower(%{creator_id: creator.id, discord_channel_id: discord_channel_id})
      generate_follower(%{creator_id: creator.id, discord_channel_id: Faker.String.base64()})

      {:ok, following_list} = Creators.channel_following_list(discord_channel_id)
      assert following_list == [creator.code]
    end
  end

  describe "channel_follower" do
    test "find follower for creator code by channel_id" do
      creator = generate_creator()
      guild = generate_guild()

      follower = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      {:ok, ^follower} =
        Creators.channel_follower({:twitch, creator.code}, %{
          channel_id: follower.discord_channel_id
        })
    end

    test "not_found if no creator by that code" do
      creator = generate_creator()
      guild = generate_guild()

      follower = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      {:error, :not_found} =
        Creators.channel_follower({:twitch, Faker.String.base64()}, %{
          channel_id: follower.discord_channel_id
        })
    end

    test "not_found if no follower for that channel_id by that code" do
      creator = generate_creator()

      {:error, :not_found} =
        Creators.channel_follower({:twitch, creator.code}, %{
          channel_id: Faker.String.base64()
        })
    end
  end
end
