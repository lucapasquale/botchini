defmodule Botchini.Schema.StreamFollower do
  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Schema.{Stream, StreamFollower}

  schema "stream_followers" do
    field(:channel_id, :string, null: false)

    belongs_to :stream, Stream

    timestamps()
  end

  def find_all_for_stream(stream_id) do
    StreamFollower
    |> Ecto.Query.where(stream_id: ^stream_id)
    |> Botchini.Repo.all
  end

  defp changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:channel_id, :stream_id, :inserted_at, :updated_at])
    |> validate_required([:channel_id, :stream_id])
  end
end
