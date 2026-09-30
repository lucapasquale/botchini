defmodule Botchini.Creators.Schema.Follower do
  @moduledoc """
  Schema representing a discord channel following a creator
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Creators.Schema.{Creator, Follower}
  alias Botchini.Discord.Schema.Guild

  @type t :: %__MODULE__{
          creator_id: String.t(),
          guild_id: String.t() | nil,
          discord_channel_id: String.t(),
          discord_user_id: String.t() | nil
        }

  schema "followers" do
    field(:discord_channel_id, :string)
    field(:discord_user_id, :string)

    belongs_to(:creator, Creator)
    belongs_to(:guild, Guild)

    timestamps()
  end

  @spec changeset(Follower.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Follower{} = follower, attrs \\ %{}) do
    follower
    |> cast(attrs, [:discord_channel_id, :discord_user_id, :creator_id, :guild_id])
    |> validate_required([:discord_channel_id, :creator_id])
  end
end
