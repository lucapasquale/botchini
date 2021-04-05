defmodule Botchini.Schema.StreamFollower do
  @moduledoc """
  Schema representing a discord channel following a stream
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset

  alias Botchini.Schema.{Stream, StreamFollower}

  @type t :: %__MODULE__{
          stream_id: String.t(),
          discord_guild_id: String.t(),
          discord_channel_id: String.t(),
          discord_user_id: String.t()
        }

  schema "stream_followers" do
    field(:discord_guild_id, :string, null: false)
    field(:discord_channel_id, :string, null: false)
    field(:discord_user_id, :string, null: false)

    belongs_to(:stream, Stream)
    timestamps()
  end

  @spec find(String.t(), String.t()) :: StreamFollower.t() | nil
  def find(stream_id, discord_channel_id) do
    StreamFollower
    |> Ecto.Query.where(stream_id: ^stream_id)
    |> Ecto.Query.where(discord_channel_id: ^discord_channel_id)
    |> Botchini.Repo.one()
  end

  @spec find_all_for_stream(String.t()) :: [StreamFollower.t()]
  def find_all_for_stream(stream_id) do
    StreamFollower
    |> Ecto.Query.where(stream_id: ^stream_id)
    |> Botchini.Repo.all()
  end

  @spec insert(Ecto.Schema.t()) :: StreamFollower.t()
  def insert(follower) do
    {:ok, inserted} =
      follower
      |> changeset()
      |> Botchini.Repo.insert()

    inserted
  end

  @spec delete(StreamFollower.t()) :: {:ok, StreamFollower.t()} | {:err, any()}
  def delete(follower) do
    if follower != nil do
      Botchini.Repo.delete(follower)
    end
  end

  defp changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:discord_guild_id, :discord_channel_id, :discord_user_id, :stream_id])
    |> validate_required([:discord_channel_id, :stream_id])
  end
end
