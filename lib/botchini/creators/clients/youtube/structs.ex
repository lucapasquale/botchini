defmodule Botchini.Creators.Clients.Youtube.Structs.Channel do
  @moduledoc """
  Channel from YouTube API
  """

  defstruct [:id, :snippet, :statistics]

  @type thumbnail :: %{
          url: String.t(),
          width: integer(),
          height: integer()
        }

  @type snippet :: %{
          title: String.t(),
          description: String.t(),
          customUrl: String.t(),
          publishedAt: String.t(),
          thumbnails: %{
            default: thumbnail(),
            medium: thumbnail(),
            high: thumbnail()
          }
        }

  @type statistics :: %{
          subscriberCount: String.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          snippet: snippet(),
          statistics: statistics()
        }

  use ExConstructor
end

defmodule Botchini.Creators.Clients.Youtube.Structs.Video do
  @moduledoc """
  Video from YouTube API
  """

  defstruct [:id, :snippet, :statistics, liveStreamingDetails: nil]

  @type thumbnail :: %{
          url: String.t(),
          width: integer(),
          height: integer()
        }

  @type snippet :: %{
          title: String.t(),
          description: String.t(),
          channelId: String.t(),
          channelTitle: String.t(),
          publishedAt: String.t(),
          thumbnails: %{
            default: thumbnail(),
            medium: thumbnail(),
            high: thumbnail(),
            standard: thumbnail(),
            maxres: thumbnail()
          }
        }

  @type statistics :: %{
          viewCount: String.t(),
          likeCount: String.t(),
          favoriteCount: String.t(),
          commentCount: String.t()
        }

  @type liveStreamingDetails :: %{
          actualStartTime: String.t(),
          actualEndTime: String.t(),
          scheduledStartTime: String.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          snippet: snippet(),
          statistics: statistics(),
          liveStreamingDetails: liveStreamingDetails() | nil
        }

  use ExConstructor
end
