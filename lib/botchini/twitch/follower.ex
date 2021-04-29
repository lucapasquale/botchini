defmodule Botchini.Twitch.Follower do
  @moduledoc """
  Schema representing a discord channel following a stream
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Schema.{Guild}
  alias Botchini.Twitch.{Stream, Follower}

  @type t :: %__MODULE__{
          stream_id: String.t(),
          guild_id: String.t(),
          discord_channel_id: String.t(),
          discord_user_id: String.t()
        }

  schema "stream_followers" do
    field(:discord_channel_id, :string, null: false)
    field(:discord_user_id, :string, null: false)

    belongs_to(:stream, Stream)
    belongs_to(:guild, Guild)
    timestamps()
  end

  @doc false
  def changeset(%Follower{} = follower, attrs \\ %{}) do
    follower
    |> cast(attrs, [:discord_channel_id, :discord_user_id, :stream_id, :guild_id])
    |> validate_required([:discord_channel_id, :discord_user_id, :stream_id, :guild_id])
  end
end
