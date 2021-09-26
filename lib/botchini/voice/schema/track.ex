defmodule Botchini.Voice.Schema.Track do
  @moduledoc """
  Schema representing a voice track
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Voice.Schema.Track

  @type t :: %__MODULE__{
          guild_id: String.t(),
          play_url: String.t(),
          status: :waiting | :playing | :paused | :done
        }

  schema "voice_tracks" do
    field(:play_url, :string, null: false)
    field(:status, Ecto.Enum, values: [:waiting, :playing, :paused, :done], null: false)

    belongs_to(:guild, Guild)

    timestamps()
  end

  @spec changeset(Track.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Track{} = track, attrs \\ %{}) do
    track
    |> cast(attrs, [:play_url, :status, :guild_id])
    |> validate_required([:play_url, :status, :guild_id])
  end
end
