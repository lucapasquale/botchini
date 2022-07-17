defmodule Botchini.Creators.Clients.Youtube.Structs.Channel do
  @moduledoc """
  Channel from YouTube API
  """

  defstruct [:id, :snippet]

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

  @type t :: %__MODULE__{
          id: String.t(),
          snippet: snippet()
        }

  use ExConstructor
end

defmodule Botchini.Creators.Clients.Youtube.Structs.Video do
  @moduledoc """
  Video from YouTube API
  """

  defstruct [:id, :snippet, liveStreamingDetails: nil]

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

  @type liveStreamingDetails :: %{
          actualStartTime: String.t(),
          actualEndTime: String.t(),
          scheduledStartTime: String.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          snippet: snippet(),
          liveStreamingDetails: liveStreamingDetails() | nil
        }

  use ExConstructor
end
