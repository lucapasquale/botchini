defmodule BotchiniTest.Services.ServicesTest do
  use Botchini.DataCase, async: false

  use Patch

  alias Botchini.Services
  alias Botchini.Services.{Twitch, Youtube}

  describe "twitch_user_info" do
    test "calls Twitch API" do
      patch(Twitch, :get_user, nil)

      user_id = Faker.String.base64()
      nil = Services.twitch_user_info(user_id)

      assert_called(Twitch.get_user(user_id))
    end
  end

  describe "twitch_stream_info" do
    test "calls Twitch API" do
      patch(Twitch, :get_stream, nil)

      service_id = Faker.String.base64()
      nil = Services.twitch_stream_info(service_id)

      assert_called(Twitch.get_stream(service_id))
    end
  end

  describe "youtube_channel_info" do
    test "calls Youtube API" do
      patch(Youtube, :get_channel, nil)

      channel_id = Faker.String.base64()
      nil = Services.youtube_channel_info(channel_id)

      assert_called(Youtube.get_channel(channel_id))
    end
  end

  describe "youtube_video_info" do
    test "calls Youtube API" do
      patch(Youtube, :get_video, nil)

      video_id = Faker.String.base64()
      nil = Services.youtube_video_info(video_id)

      assert_called(Youtube.get_video(video_id))
    end
  end

  describe "get_user" do
    test "calls Twitch API returning nil" do
      patch(Twitch, :get_user, nil)

      {:error, :not_found} = Services.get_user(:twitch, Faker.String.base64())
    end

    test "calls Twitch API returning user" do
      id = Faker.String.base64()
      name = Faker.String.base64()

      patch(Twitch, :get_user, %{id: id, display_name: name})

      {:ok, {^id, ^name}} = Services.get_user(:twitch, Faker.String.base64())
    end

    test "calls Youtube API returning nil" do
      patch(Youtube, :get_channel, nil)

      {:error, :not_found} = Services.get_user(:youtube, Faker.String.base64())
    end

    test "calls Youtube API returning user" do
      id = Faker.String.base64()
      name = Faker.String.base64()
      patch(Youtube, :get_channel, %{id: id, snippet: %{"title" => name}})

      {:ok, {^id, ^name}} = Services.get_user(:youtube, Faker.String.base64())
    end
  end

  describe "search_channel" do
    test "calls Twitch API returning nil to both" do
      patch(Twitch, :get_user_by_user_login, nil)
      patch(Twitch, :search_channels, [])

      term = Faker.String.base64()
      {:error, :not_found} = Services.search_channel(:twitch, term)

      assert_called(Twitch.get_user_by_user_login(term))
      assert_called(Twitch.search_channels(term))
    end

    test "calls Twitch API returning first channel" do
      id = Faker.String.base64()
      name = Faker.String.base64()

      patch(Twitch, :get_user_by_user_login, nil)
      patch(Twitch, :search_channels, [%{id: id, display_name: name}])

      {:ok, {^id, ^name}} = Services.search_channel(:twitch, Faker.String.base64())
    end

    test "calls Twitch API returns directly from user" do
      id = Faker.String.base64()
      name = Faker.String.base64()

      patch(Twitch, :get_user_by_user_login, %{id: id, display_name: name})

      {:ok, {^id, ^name}} = Services.search_channel(:twitch, Faker.String.base64())

      refute_called(Twitch.search_channels(_))
    end

    test "calls Youtube API returns first channel" do
      id = Faker.String.base64()
      name = Faker.String.base64()
      patch(Youtube, :search_channels, [%{id: id, snippet: %{"title" => name}}])

      term = Faker.String.base64()
      {:ok, {^id, ^name}} = Services.search_channel(:youtube, term)

      assert_called(Youtube.search_channels(term))
    end

    test "calls Youtube API returns :not_found" do
      patch(Youtube, :search_channels, [])

      {:error, :not_found} = Services.search_channel(:youtube, Faker.String.base64())
    end
  end

  describe "subscribe_to_service" do
    test "calls Twitch API" do
      webhook_id = Faker.String.base64()
      patch(Twitch, :add_stream_webhook, %{"id" => webhook_id})

      service_id = Faker.String.base64()
      ^webhook_id = Services.subscribe_to_service(:twitch, service_id)

      assert_called(Twitch.add_stream_webhook(service_id))
    end

    test "calls Youtube API" do
      patch(Youtube, :manage_channel_pubsub, {:ok})

      service_id = Faker.String.base64()
      nil = Services.subscribe_to_service(:youtube, service_id)

      assert_called(Youtube.manage_channel_pubsub(service_id, true))
    end
  end

  describe "unsubscribe_from_service" do
    test "calls Twitch API" do
      patch(Twitch, :delete_stream_webhook, nil)

      webhook_id = Faker.String.base64()
      {:ok} = Services.unsubscribe_from_service(:twitch, {nil, webhook_id})

      assert_called(Twitch.delete_stream_webhook(webhook_id))
    end

    test "calls Youtube API" do
      patch(Youtube, :manage_channel_pubsub, nil)

      service_id = Faker.String.base64()
      {:ok} = Services.unsubscribe_from_service(:youtube, {service_id, nil})

      assert_called(Youtube.manage_channel_pubsub(service_id, false))
    end
  end
end
