defmodule Botchini.Schema.StreamFollower do
  @moduledoc """
  Schema representing a discord channel following a stream
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Schema.{Stream, StreamFollower}

  def find(stream_id, discord_channel_id) do
    StreamFollower
    |> Ecto.Query.where(stream_id: ^stream_id)
    |> Ecto.Query.where(discord_channel_id: ^discord_channel_id)
    |> Botchini.Repo.one()
  end

  def find_all_for_stream(stream_id) do
    StreamFollower
    |> Ecto.Query.where(stream_id: ^stream_id)
    |> Botchini.Repo.all()
  end

  def insert(follower) do
    {:ok, inserted} =
      follower
      |> changeset()
      |> Botchini.Repo.insert()

    inserted
  end

  def delete(follower) do
    if follower != nil do
      Botchini.Repo.delete(follower)
    end
  end

  schema "stream_followers" do
    field(:discord_channel_id, :string, null: false)

    belongs_to(:stream, Stream)

    timestamps()
  end

  defp changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:discord_channel_id, :stream_id])
    |> validate_required([:discord_channel_id, :stream_id])
  end
end
