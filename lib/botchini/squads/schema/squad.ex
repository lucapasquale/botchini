defmodule Botchini.Squads.Schema.Squad do
  @moduledoc """
  Schema representing a squad
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Squads.Schema.{Squad, SquadMember}

  @type t :: %__MODULE__{
          name: String.t()
        }

  schema "squads" do
    field(:name, :string)

    belongs_to(:guild, Guild)
    has_many(:squad_member, SquadMember)

    timestamps()
  end

  @spec changeset(Squad.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Squad{} = squad, attrs \\ %{}) do
    squad
    |> cast(attrs, [:name, :guild_id])
    |> validate_required([:name, :guild_id])
  end
end
