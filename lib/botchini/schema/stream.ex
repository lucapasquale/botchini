defmodule Botchini.Schema.Stream do
  @moduledoc """
  Schema representing a twitch stream
  """

  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  alias Botchini.Schema.{Stream, StreamFollower}

  @type t :: %__MODULE__{
          code: String.t(),
          twitch_user_id: String.t(),
          twitch_subscription_id: String.t()
        }

  schema "streams" do
    field(:code, :string, null: false)
    field(:twitch_user_id, :string, null: false)
    field(:twitch_subscription_id, :string, null: false)

    has_many(:stream_followers, StreamFollower)

    timestamps()
  end

  @spec find_by_code(String.t()) :: Stream.t() | nil
  def find_by_code(code) do
    Botchini.Repo.get_by(Stream, code: code)
  end

  @spec find_by_twitch_user_id(String.t()) :: Stream.t() | nil
  def find_by_twitch_user_id(twitch_user_id) do
    Botchini.Repo.get_by(Stream, twitch_user_id: twitch_user_id)
  end

  @spec find_all_for_guild(String.t()) :: [{String.t(), String.t()}]
  def find_all_for_guild(guild_id) do
    Botchini.Repo.all(
      from(s in Stream,
        join: sf in StreamFollower,
        on: sf.stream_id == s.id,
        where: sf.guild_id == ^guild_id,
        select: {sf.discord_channel_id, s.code}
      )
    )
  end

  @spec insert(Ecto.Schema.t()) :: Stream.t()
  def insert(stream) do
    {:ok, inserted} =
      stream
      |> changeset()
      |> Botchini.Repo.insert()

    inserted
  end

  @spec delete_stream(Stream.t()) :: {:ok, Stream.t()} | {:err, any()}
  def delete_stream(stream) do
    case find_by_code(stream.code) do
      %Stream{} = existing -> Botchini.Repo.delete(existing)
      nil -> nil
    end
  end

  defp changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:code, :twitch_user_id, :twitch_subscription_id])
    |> validate_required([:code, :twitch_user_id, :twitch_subscription_id])
    |> unique_constraint(:code)
    |> unique_constraint(:twitch_user_id)
  end
end
