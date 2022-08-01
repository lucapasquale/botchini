defmodule BotchiniTest.Creators.CreatorsTest do
  use Botchini.DataCase, async: false

  use Patch

  alias Botchini.{Creators, Repo, Services}
  alias Botchini.Creators.Schema.{Creator, Follower}

  describe "find_by_service" do
    test "find creator by its service and service_id" do
      creator = generate_creator()

      ^creator = Creators.find_by_service(creator.service, creator.service_id)
    end

    test "return nil of not found" do
      nil = Creators.find_by_service(:twitch, Faker.String.base64())
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
    test "should find followed creators for same service by similar term" do
      channel_id = Faker.String.base64()

      creator_1 = generate_creator(%{service: :twitch, name: "myTest1"})
      generate_follower(%{creator_id: creator_1.id, discord_channel_id: channel_id})

      creator_2 = generate_creator(%{service: :twitch, name: "myTest2"})
      generate_follower(%{creator_id: creator_2.id, discord_channel_id: channel_id})

      creator_3 = generate_creator(%{service: :youtube, name: "myTest2"})
      generate_follower(%{creator_id: creator_3.id, discord_channel_id: channel_id})

      response =
        Creators.search_following_creators({creator_1.service, "test"}, %{channel_id: channel_id})

      assert response == [{creator_1.id, creator_1.name}, {creator_2.id, creator_2.name}]
    end

    test "should return everything if term is empty string" do
      channel_id = Faker.String.base64()

      creator_1 = generate_creator(%{name: "qwer"})
      generate_follower(%{creator_id: creator_1.id, discord_channel_id: channel_id})

      creator_2 = generate_creator(%{service: creator_1.service, name: "asdf"})
      generate_follower(%{creator_id: creator_2.id, discord_channel_id: channel_id})

      creator_3 = generate_creator(%{service: creator_1.service, name: "zxcv"})
      generate_follower(%{creator_id: creator_3.id, discord_channel_id: channel_id})

      response =
        Creators.search_following_creators({creator_1.service, ""}, %{channel_id: channel_id})

      assert response == [
               {creator_1.id, creator_1.name},
               {creator_2.id, creator_2.name},
               {creator_3.id, creator_3.name}
             ]
    end

    test "should empty if term does not match" do
      channel_id = Faker.String.base64()

      creator = generate_creator(%{name: "qwer"})
      generate_follower(%{creator_id: creator.id, discord_channel_id: channel_id})

      response =
        Creators.search_following_creators({creator.service, "asdf"}, %{channel_id: channel_id})

      assert response == []
    end

    test "should empty if no creator in channel" do
      response =
        Creators.search_following_creators({:twitch, "test"}, %{
          channel_id: Faker.String.base64()
        })

      assert response == []
    end

    test "should ignore creator if term does not match" do
      channel_id = Faker.String.base64()

      creator = generate_creator(%{name: "valid"})
      generate_follower(%{creator_id: creator.id, discord_channel_id: channel_id})

      invalid_creator = generate_creator(%{service: creator.service, name: "somethingElse"})
      generate_follower(%{creator_id: invalid_creator.id, discord_channel_id: channel_id})

      response =
        Creators.search_following_creators({creator.service, "valid"}, %{channel_id: channel_id})

      assert response == [{creator.id, creator.name}]
    end

    test "should ignore creator if its from different channel_id" do
      channel_id = Faker.String.base64()

      creator = generate_creator(%{name: "myTest1"})
      generate_follower(%{creator_id: creator.id, discord_channel_id: channel_id})

      invalid_creator = generate_creator(%{service: creator.service, name: "myTest2"})
      generate_follower(%{creator_id: invalid_creator.id})

      response =
        Creators.search_following_creators({creator.service, "test"}, %{channel_id: channel_id})

      assert response == [{creator.id, creator.name}]
    end
  end

  describe "upsert" do
    test "creates new creator on DB and on service" do
      name = Faker.String.base64()
      service = :twitch
      service_id = Faker.String.base64()
      webhook_id = Faker.String.base64()

      patch(Services, :get_user, {:ok, {service_id, name}})
      patch(Services, :subscribe_to_service, webhook_id)

      {:ok, creator} = Creators.upsert(service, service_id)

      assert creator.name == name
      assert creator.service == service
      assert creator.service_id == service_id
      assert creator.webhook_id == webhook_id

      assert_called(Services.get_user(service, service_id))
      assert_called(Services.subscribe_to_service(service, service_id))
    end

    test "returns existing creator from DB" do
      creator = generate_creator()
      {:ok, ^creator} = Creators.upsert(creator.service, creator.service_id)

      refute_called(Services.get_user(_, _))
      refute_called(Services.subscribe_to_service(_, _))
    end

    test "returns error if creator not found on service" do
      patch(Services, :get_user, {:error, :not_found})

      service = :twitch
      service_id = Faker.String.base64()

      {:error, :invalid_creator} = Creators.upsert(service, service_id)

      assert_called(Services.get_user(service, service_id))
      refute_called(Services.subscribe_to_service(_, _))
    end
  end

  describe "follow" do
    test "start following creator" do
      creator = generate_creator()
      guild = generate_guild()
      message = generate_message()

      {:ok, follower} = Creators.follow(creator, guild, message)

      assert follower.guild_id == guild.id
      assert follower.discord_user_id == message.user_id
      assert follower.discord_channel_id == message.channel_id
    end

    test "follow from direct message" do
      creator = generate_creator()
      message = %{channel_id: Faker.String.base64(), user_id: nil}

      {:ok, follower} = Creators.follow(creator, nil, message)

      assert follower.guild_id == nil
      assert follower.discord_user_id == nil
      assert follower.discord_channel_id == message.channel_id
    end

    test "already_following if channel was already following" do
      creator = generate_creator()
      guild = generate_guild()
      follower = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      message = %{
        channel_id: follower.discord_channel_id,
        user_id: follower.discord_user_id
      }

      {:error, :already_following} = Creators.follow(creator, nil, message)
    end

    defp generate_message,
      do: %{
        user_id: Faker.String.base64(),
        channel_id: Faker.String.base64()
      }
  end

  describe "unfollow" do
    test "stop following, delete creator and remove subscription if no more followers" do
      patch(Services, :unsubscribe_from_service, {:ok})

      creator = generate_creator()
      follower = generate_follower(%{creator_id: creator.id})

      {:ok, ^creator} =
        Creators.unfollow(creator.id, %{
          channel_id: follower.discord_channel_id
        })

      refute Repo.get_by(Creator, id: creator.id)
      refute Repo.get_by(Follower, id: follower.id)

      assert_called(Services.unsubscribe_from_service(_, _))
    end

    test "stop following, but don't delete creator if has other followers" do
      patch(Services, :unsubscribe_from_service, {:ok})

      creator = generate_creator()
      follower = generate_follower(%{creator_id: creator.id})
      generate_follower(%{creator_id: creator.id})

      {:ok, ^creator} =
        Creators.unfollow(creator.id, %{
          channel_id: follower.discord_channel_id
        })

      assert Repo.get_by(Creator, id: creator.id)
      refute Repo.get_by(Follower, id: follower.id)

      refute_called(Services.unsubscribe_from_service(_, _))
    end

    test "not_found if creator was not found" do
      creator = generate_creator()
      guild = generate_guild()
      follower = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      {:error, :not_found} =
        Creators.unfollow(-1, %{
          channel_id: follower.discord_channel_id
        })
    end

    test "not_found if follower was not found" do
      creator = generate_creator()

      {:error, :not_found} =
        Creators.unfollow(creator.id, %{
          channel_id: Faker.String.base64()
        })
    end
  end

  describe "guild_following_list" do
    test "lists all follower.channel_id and creator.name for a guild" do
      creator_1 = generate_creator()
      creator_2 = generate_creator()

      guild = generate_guild()

      follower_1 = generate_follower(%{creator_id: creator_1.id, guild_id: guild.id})
      follower_2 = generate_follower(%{creator_id: creator_2.id, guild_id: guild.id})

      {:ok, following_list} = Creators.guild_following_list(guild)

      assert length(following_list) == 2
      assert Enum.at(following_list, 0) == {follower_1.discord_channel_id, creator_1.name}
      assert Enum.at(following_list, 1) == {follower_2.discord_channel_id, creator_2.name}
    end

    test "lists for same creator but different followers" do
      creator = generate_creator()
      guild = generate_guild()

      follower_1 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})
      follower_2 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      {:ok, following_list} = Creators.guild_following_list(guild)

      assert length(following_list) == 2
      assert Enum.at(following_list, 0) == {follower_1.discord_channel_id, creator.name}
      assert Enum.at(following_list, 1) == {follower_2.discord_channel_id, creator.name}
    end

    test "ignores followers from other guild" do
      creator = generate_creator()
      guild = generate_guild()
      other_guild = generate_guild()

      follower_1 = generate_follower(%{creator_id: creator.id, guild_id: guild.id})
      generate_follower(%{creator_id: creator.id, guild_id: other_guild.id})

      {:ok, following_list} = Creators.guild_following_list(guild)

      assert length(following_list) == 1
      assert Enum.at(following_list, 0) == {follower_1.discord_channel_id, creator.name}
    end
  end

  describe "channel_following_list" do
    test "lists all follower.channel_id and creator.name for a guild" do
      creator_1 = generate_creator()
      creator_2 = generate_creator()

      discord_channel_id = Faker.String.base64()
      generate_follower(%{creator_id: creator_1.id, discord_channel_id: discord_channel_id})
      generate_follower(%{creator_id: creator_2.id, discord_channel_id: discord_channel_id})

      {:ok, following_list} = Creators.channel_following_list(discord_channel_id)
      assert following_list == [creator_1.name, creator_2.name]
    end

    test "ignores followers from other channel" do
      creator = generate_creator()

      discord_channel_id = Faker.String.base64()
      generate_follower(%{creator_id: creator.id, discord_channel_id: discord_channel_id})
      generate_follower(%{creator_id: creator.id, discord_channel_id: Faker.String.base64()})

      {:ok, following_list} = Creators.channel_following_list(discord_channel_id)
      assert following_list == [creator.name]
    end
  end

  describe "discord_channel_follower" do
    test "find follower for creator code by channel_id" do
      creator = generate_creator()
      guild = generate_guild()

      follower = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      {:ok, ^follower} =
        Creators.discord_channel_follower(creator.id, %{
          channel_id: follower.discord_channel_id
        })
    end

    test "not_found if no creator found" do
      creator = generate_creator()
      guild = generate_guild()

      follower = generate_follower(%{creator_id: creator.id, guild_id: guild.id})

      {:error, :not_found} =
        Creators.discord_channel_follower(-1, %{
          channel_id: follower.discord_channel_id
        })
    end

    test "not_found if no follower for that channel_id" do
      creator = generate_creator()

      {:error, :not_found} =
        Creators.discord_channel_follower(creator.id, %{
          channel_id: Faker.String.base64()
        })
    end
  end
end
