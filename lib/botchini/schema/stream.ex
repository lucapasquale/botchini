defmodule Botchini.Schema.Stream do
  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Schema.{Stream, StreamFollower}

  schema "streams" do
    field(:code, :string, null: false)
    field(:twitch_user_id, :string, null: false)
    field(:twitch_subscription_id, :string, null: false)

    has_many(:stream_followers, StreamFollower)

    timestamps()
  end

  def find_by_code(code) do
    Botchini.Repo.get_by(Stream, code: code)
  end

  def find_all do
    Stream
    |> Botchini.Repo.all()
  end

  def insert(stream) do
    {:ok, inserted} =
      stream
      |> changeset()
      |> Botchini.Repo.insert()

    inserted
  end

  def update_stream(stream, payload) do
    Botchini.Repo.get(Stream, stream.id)
    |> changeset(payload)
    |> Botchini.Repo.update()
  end

  defp changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:code, :twitch_user_id, :twitch_subscription_id])
    |> validate_required([:code, :twitch_user_id, :twitch_subscription_id])
    |> unique_constraint(:twitch_user_id)
  end
end
