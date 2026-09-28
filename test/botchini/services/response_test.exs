defmodule BotchiniTest.Services.ResponseTest do
  use ExUnit.Case, async: true

  alias Botchini.Services.Twitch.Structs.{Stream, User}
  alias Botchini.Services.Youtube.Structs.{Channel, Video}

  test "builds YouTube videos, ignoring fields they don't define" do
    item = %{
      "kind" => "youtube#video",
      "etag" => "tS9_Fj-vNJyS-tupSP72kw",
      "id" => "dQw4w9WgXcQ",
      "snippet" => %{"title" => "Live now"},
      "liveStreamingDetails" => %{"actualStartTime" => "2026-09-28T00:00:00Z"}
    }

    assert %Video{
             id: "dQw4w9WgXcQ",
             snippet: %{"title" => "Live now"},
             liveStreamingDetails: %{"actualStartTime" => _}
           } = Video.new(item)

    assert %Video{liveStreamingDetails: nil} =
             Video.new(Map.delete(item, "liveStreamingDetails"))
  end

  test "builds YouTube channels from API items and atom maps" do
    item = %{"kind" => "youtube#channel", "etag" => "abc", "id" => "UC1", "snippet" => %{}}

    assert %Channel{id: "UC1", snippet: %{}} = Channel.new(item)
    assert %Channel{id: "UC2"} = Channel.new(%{id: "UC2", snippet: %{}})
  end

  test "builds Twitch streams with fields added to the API" do
    stream = %{
      "id" => "1",
      "user_login" => "luca",
      "title" => "Elden Ring",
      "tags" => ["English"],
      "is_mature" => false
    }

    assert %Stream{id: "1", user_login: "luca", title: "Elden Ring", tag_ids: []} =
             Stream.new(stream)
  end

  test "keeps struct defaults for missing fields" do
    assert %User{id: "1", login: "luca", view_count: 0} =
             User.new(%{"id" => "1", "login" => "luca"})
  end
end
