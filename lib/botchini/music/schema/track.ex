defmodule Botchini.Music.Schema.Track do
  @moduledoc """
  Schema representing a music track
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Music.Schema.Track

  @type t :: %__MODULE__{
          guild_id: String.t(),
          play_url: String.t(),
          title: String.t(),
          status: :waiting | :playing | :paused | :done
        }

  schema "music_tracks" do
    field(:play_url, :string)
    field(:title, :string)
    field(:status, Ecto.Enum, values: [:waiting, :playing, :paused, :done])

    belongs_to(:guild, Guild)

    timestamps()
  end

  @spec changeset(Track.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Track{} = track, attrs \\ %{}) do
    track
    |> cast(attrs, [:play_url, :title, :status, :guild_id])
    |> validate_required([:play_url, :title, :status, :guild_id])
  end
end
