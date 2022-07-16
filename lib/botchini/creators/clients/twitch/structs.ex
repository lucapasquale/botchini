defmodule Botchini.Creators.Clients.Twitch.Structs.User do
  @moduledoc """
  User from Twitch API
  """

  defstruct id: "",
            login: "",
            display_name: "",
            type: "",
            broadcaster_type: "",
            description: "",
            profile_image_url: "",
            offline_image_url: "",
            view_count: 0,
            created_at: ""

  @type t :: %__MODULE__{
          id: String.t(),
          login: String.t(),
          display_name: String.t(),
          type: String.t(),
          broadcaster_type: String.t(),
          description: String.t(),
          profile_image_url: String.t(),
          offline_image_url: String.t(),
          view_count: integer(),
          created_at: String.t()
        }

  use ExConstructor
end

defmodule Botchini.Creators.Clients.Twitch.Structs.Stream do
  @moduledoc """
  Stream from Twitch API
  """

  defstruct id: "",
            user_id: "",
            user_login: "",
            user_name: "",
            game_id: "",
            game_name: "",
            type: "",
            title: "",
            viewer_count: 0,
            started_at: "",
            language: "",
            thumbnail_url: "",
            tag_ids: [],
            is_mature: false

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          user_login: String.t(),
          user_name: String.t(),
          game_id: String.t(),
          game_name: String.t(),
          type: String.t(),
          title: String.t(),
          viewer_count: integer(),
          started_at: String.t(),
          language: String.t(),
          thumbnail_url: String.t(),
          tag_ids: [String.t()],
          is_mature: boolean()
        }

  use ExConstructor
end

defmodule Botchini.Creators.Clients.Twitch.Structs.Channel do
  @moduledoc """
  Channel from Twitch API
  """

  defstruct id: "",
            display_name: "",
            broadcaster_login: "",
            broadcaster_language: "",
            game_id: "",
            game_name: "",
            title: "",
            thumbnail_url: "",
            is_live: false,
            started_at: "",
            tag_id: []

  @type t :: %__MODULE__{
          id: String.t(),
          display_name: String.t(),
          broadcaster_login: String.t(),
          broadcaster_language: String.t(),
          game_id: String.t(),
          game_name: String.t(),
          title: String.t(),
          thumbnail_url: String.t(),
          is_live: boolean(),
          started_at: String.t(),
          tag_id: [String.t()]
        }

  use ExConstructor
end
