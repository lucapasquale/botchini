defmodule Botchini.Schema.Stream do
  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Schema.{Stream, StreamFollower}

  schema "streams" do
    field(:code, :string, null: false)
    field(:online, :boolean, null: false, default: false)

    has_many(:stream_followers, StreamFollower)

    timestamps()
  end

  def find_all do
    Stream
    |> Botchini.Repo.all
  end

  def update_stream(stream, payload) do
    Botchini.Repo.get(Stream, stream.id)
    |> changeset(payload)
    |> Botchini.Repo.update()
  end

  def get_or_insert_stream(stream) do
    find_by_code(stream.code) || insert(stream)
  end

  def delete_stream(stream) do
    case find_by_code(stream.code) do
      %Stream{} = existing -> Botchini.Repo.delete(existing)
      nil -> nil
    end
  end

  defp find_by_code(code) do
    Stream
    |> Botchini.Repo.get_by(code: code)
  end

  defp insert(stream) do
    stream
    |> changeset()
    |> Botchini.Repo.insert()
  end

  defp changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:code, :online, :inserted_at, :updated_at])
    |> validate_required([:code])
    |> unique_constraint(:code)
  end
end
