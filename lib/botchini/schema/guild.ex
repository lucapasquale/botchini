defmodule Botchini.Schema.Guild do
  @moduledoc """
  Schema representing a discord guild
  """

  use Ecto.Schema
  require Ecto.Query
  # import Ecto.Changeset

  alias Botchini.Schema.{Guild, StreamFollower}

  @type t :: %__MODULE__{
          discord_guild_id: String.t()
        }

  schema "guilds" do
    field(:discord_guild_id, :string, null: false)

    has_many(:stream_followers, StreamFollower)

    timestamps()
  end

  @spec find(String.t()) :: Guild.t() | nil
  def find(discord_guild_id) do
    Botchini.Repo.get_by(Guild, discord_guild_id: discord_guild_id)
  end

  # defp changeset(struct, params \\ %{}) do
  #   struct
  #   |> cast(params, [:discord_guild_id])
  #   |> validate_required([:discord_guild_id])
  #   |> unique_constraint(:discord_guild_id)
  # end
end
