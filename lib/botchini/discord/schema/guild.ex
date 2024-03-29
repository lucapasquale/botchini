defmodule Botchini.Discord.Schema.Guild do
  @moduledoc """
  Schema representing a discord guild
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Creators.Schema.Follower
  alias Botchini.Discord.Schema.Guild

  @type t :: %__MODULE__{
          discord_guild_id: String.t()
        }

  schema "guilds" do
    field(:discord_guild_id, :string)

    has_many(:stream_followers, Follower)

    timestamps()
  end

  @spec changeset(Guild.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Guild{} = guild, attrs \\ %{}) do
    guild
    |> cast(attrs, [:discord_guild_id])
    |> validate_required([:discord_guild_id])
    |> unique_constraint(:discord_guild_id)
  end
end
