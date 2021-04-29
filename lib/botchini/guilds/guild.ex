defmodule Botchini.Guilds.Guild do
  @moduledoc """
  Schema representing a discord guild
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Guilds.Guild
  alias Botchini.Twitch.{Follower}

  @type t :: %__MODULE__{
          discord_guild_id: String.t()
        }

  schema "guilds" do
    field(:discord_guild_id, :string, null: false)

    has_many(:stream_followers, Follower)

    timestamps()
  end

  @doc false
  def changeset(%Guild{} = guild, attrs \\ %{}) do
    guild
    |> cast(attrs, [:discord_guild_id])
    |> validate_required([:discord_guild_id])
    |> unique_constraint(:discord_guild_id)
  end
end
