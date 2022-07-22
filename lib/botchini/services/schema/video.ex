defmodule Botchini.Services.Schema.Video do
  @moduledoc """
  Schema representing a video from YouTube
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Services.Schema.Video

  @type t :: %__MODULE__{
          channel_id: String.t(),
          video_id: String.t()
        }

  schema "videos" do
    field(:channel_id, :string)
    field(:video_id, :string)

    timestamps()
  end

  @spec changeset(Video.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Video{} = video, attrs \\ %{}) do
    video
    |> cast(attrs, [:channel_id, :video_id])
    |> validate_required([:channel_id, :video_id])
    |> unique_constraint(:video_id)
  end
end
