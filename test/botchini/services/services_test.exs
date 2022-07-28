defmodule BotchiniTest.Services.ServicesTest do
  use Botchini.DataCase, async: false

  import Mock

  alias Botchini.Services
  alias Botchini.Services.{Twitch, Youtube}

  describe "exists_video_by_video_id?" do
    test "returns true if finds existing video" do
      video = generate_video()

      true = Services.exists_video_by_video_id?(video.video_id)
    end

    test "returns false if no video" do
      false = Services.exists_video_by_video_id?(Faker.String.base64())
    end
  end

  describe "insert_video" do
    test "can insert a video" do
      channel_id = Faker.String.base64()
      video_id = Faker.String.base64()

      video = Services.insert_video({channel_id, video_id})

      assert(video.channel_id, channel_id)
      assert(video.video_id, video_id)
    end
  end

  describe "twitch_user_info" do
    test "calls Twitch API" do
      user_id = Faker.String.base64()

      with_mock Twitch, get_user: fn _ -> nil end do
        nil = Services.twitch_user_info(user_id)

        assert_called(Twitch.get_user(user_id))
      end
    end
  end

  describe "twitch_stream_info" do
    test "calls Twitch API" do
      service_id = Faker.String.base64()

      with_mock Twitch, get_stream: fn _ -> nil end do
        nil = Services.twitch_stream_info(service_id)

        assert_called(Twitch.get_stream(service_id))
      end
    end
  end

  describe "youtube_channel_info" do
    test "calls Youtube API" do
      channel_id = Faker.String.base64()

      with_mock Youtube, get_channel: fn _ -> nil end do
        nil = Services.youtube_channel_info(channel_id)

        assert_called(Youtube.get_channel(channel_id))
      end
    end
  end

  describe "youtube_video_info" do
    test "calls Youtube API" do
      video_id = Faker.String.base64()

      with_mock Youtube, get_video: fn _ -> nil end do
        nil = Services.youtube_video_info(video_id)

        assert_called(Youtube.get_video(video_id))
      end
    end
  end

  describe "get_user" do
    test "calls Twitch API returning nil" do
      with_mock Twitch, get_user: fn _ -> nil end do
        {:error, :not_found} = Services.get_user(:twitch, Faker.String.base64())
      end
    end

    test "calls Twitch API returning user" do
      id = Faker.String.base64()
      name = Faker.String.base64()
      user = %{id: id, display_name: name}

      with_mock Twitch, get_user: fn _ -> user end do
        {:ok, {^id, ^name}} = Services.get_user(:twitch, Faker.String.base64())
      end
    end

    test "calls Youtube API returning nil" do
      with_mock Youtube, get_channel: fn _ -> nil end do
        {:error, :not_found} = Services.get_user(:youtube, Faker.String.base64())
      end
    end

    test "calls Youtube API returning user" do
      id = Faker.String.base64()
      name = Faker.String.base64()
      channel = %{id: id, snippet: %{"title" => name}}

      with_mock Youtube, get_channel: fn _ -> channel end do
        {:ok, {^id, ^name}} = Services.get_user(:youtube, Faker.String.base64())
      end
    end
  end

  describe "search_channel" do
    test "calls Twitch API returning nil to both" do
      with_mock Twitch,
        get_user_by_user_login: fn _ -> nil end,
        search_channels: fn _ -> [] end do
        term = Faker.String.base64()

        {:error, :not_found} = Services.search_channel(:twitch, term)

        assert_called(Twitch.get_user_by_user_login(term))
        assert_called(Twitch.search_channels(term))
      end
    end

    test "calls Twitch API returning first channel" do
      id = Faker.String.base64()
      name = Faker.String.base64()
      channel = %{id: id, display_name: name}

      with_mock Twitch,
        get_user_by_user_login: fn _ -> nil end,
        search_channels: fn _ -> [channel] end do
        {:ok, {^id, ^name}} = Services.search_channel(:twitch, Faker.String.base64())
      end
    end

    test "calls Twitch API returns directly from user" do
      id = Faker.String.base64()
      name = Faker.String.base64()
      user = %{id: id, display_name: name}

      with_mock Twitch,
        get_user_by_user_login: fn _ -> user end,
        search_channels: fn _ -> [] end do
        {:ok, {^id, ^name}} = Services.search_channel(:twitch, Faker.String.base64())

        assert_not_called(Twitch.search_channels(:_))
      end
    end

    test "calls Youtube API returns first channel" do
      term = Faker.String.base64()
      id = Faker.String.base64()
      name = Faker.String.base64()

      channel = %{id: id, snippet: %{"title" => name}}

      with_mock Youtube, search_channels: fn _ -> [channel] end do
        {:ok, {^id, ^name}} = Services.search_channel(:youtube, term)

        assert_called(Youtube.search_channels(term))
      end
    end

    test "calls Youtube API returns :not_found" do
      with_mock Youtube, search_channels: fn _ -> [] end do
        {:error, :not_found} = Services.search_channel(:youtube, Faker.String.base64())
      end
    end
  end

  describe "subscribe_to_service" do
    test "calls Twitch API" do
      service_id = Faker.String.base64()

      webhook_id = Faker.String.base64()
      webhook = %{"id" => webhook_id}

      with_mock Twitch, add_stream_webhook: fn _ -> webhook end do
        ^webhook_id = Services.subscribe_to_service(:twitch, service_id)

        assert_called(Twitch.add_stream_webhook(service_id))
      end
    end

    test "calls Youtube API" do
      service_id = Faker.String.base64()

      with_mock Youtube, manage_channel_pubsub: fn _, _ -> {:ok} end do
        nil = Services.subscribe_to_service(:youtube, service_id)

        assert_called(Youtube.manage_channel_pubsub(service_id, true))
      end
    end
  end

  describe "unsubscribe_from_service" do
    test "calls Twitch API" do
      webhook_id = Faker.String.base64()

      with_mock Twitch, delete_stream_webhook: fn _ -> nil end do
        {:ok} = Services.unsubscribe_from_service(:twitch, {nil, webhook_id})

        assert_called(Twitch.delete_stream_webhook(webhook_id))
      end
    end

    test "calls Youtube API" do
      service_id = Faker.String.base64()

      with_mock Youtube, manage_channel_pubsub: fn _, _ -> nil end do
        {:ok} = Services.unsubscribe_from_service(:youtube, {service_id, nil})

        assert_called(Youtube.manage_channel_pubsub(service_id, false))
      end
    end
  end
end
