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
