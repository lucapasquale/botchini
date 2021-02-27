defmodule Botchini.Schema.StreamFollower do
  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Schema.{Stream, StreamFollower}

  schema "stream_followers" do
    field(:channel_id, :string, null: false)

    belongs_to(:stream, Stream)

    timestamps()
  end

  def get_or_insert_follower(follower) do
    find_follower(follower) || insert(follower)
  end

  def find_all_for_stream(stream_id) do
    StreamFollower
    |> Ecto.Query.where(stream_id: ^stream_id)
    |> Botchini.Repo.all()
  end

  def delete_follower(follower) do
    case find_follower(follower) do
      %StreamFollower{} = existing -> Botchini.Repo.delete(existing)
      nil -> nil
    end
  end


  defp find_follower(follower) do
    StreamFollower
    |> Ecto.Query.where(stream_id: ^follower.stream_id)
    |> Ecto.Query.where(channel_id: ^follower.channel_id)
    |> Botchini.Repo.one()
  end

  defp insert(follower) do
    {:ok, inserted} = follower
    |> changeset()
    |> Botchini.Repo.insert()

    inserted
  end

  defp changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:channel_id, :stream_id, :inserted_at, :updated_at])
    |> validate_required([:channel_id, :stream_id])
  end
end
