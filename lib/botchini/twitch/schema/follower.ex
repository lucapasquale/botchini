defmodule Botchini.Twitch.Schema.Follower do
  @moduledoc """
  Schema representing a discord channel following a stream
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Twitch.Schema.{Follower, Stream}

  @type t :: %__MODULE__{
          stream_id: String.t(),
          guild_id: String.t() | nil,
          discord_channel_id: String.t(),
          discord_user_id: String.t() | nil
        }

  schema "stream_followers" do
    field(:discord_channel_id, :string, null: false)
    field(:discord_user_id, :string, null: true)

    belongs_to(:stream, Stream)
    belongs_to(:guild, Guild)
    timestamps()
  end

  @spec changeset(Follower.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Follower{} = follower, attrs \\ %{}) do
    follower
    |> cast(attrs, [:discord_channel_id, :discord_user_id, :stream_id, :guild_id])
    |> validate_required([:discord_channel_id, :stream_id])
  end
end
