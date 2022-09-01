defmodule Botchini.Squads.Schema.SquadMember do
  @moduledoc """
  Schema representing a squad member
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Squads.Schema.{Squad, SquadMember}

  @type t :: %__MODULE__{
          discord_user_id: String.t()
        }

  schema "squad_members" do
    field(:discord_user_id, :string)

    belongs_to(:squad, Squad)

    timestamps()
  end

  @spec changeset(SquadMember.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%SquadMember{} = member, attrs \\ %{}) do
    member
    |> cast(attrs, [:discord_user_id, :squad_id])
    |> validate_required([:discord_user_id, :squad_id])
    |> unique_constraint([:discord_user_id, :squad_id])
  end
end
