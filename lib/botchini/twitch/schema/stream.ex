defmodule Botchini.Twitch.Schema.Stream do
  @moduledoc """
  Schema representing a twitch stream
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Twitch.Schema.{Follower, Stream}

  @type t :: %__MODULE__{
          code: String.t(),
          twitch_user_id: String.t(),
          twitch_subscription_id: String.t()
        }

  schema "streams" do
    field(:code, :string, null: false)
    field(:name, :string, null: true)
    field(:twitch_user_id, :string, null: false)
    field(:twitch_subscription_id, :string, null: false)

    has_many(:stream_followers, Follower)

    timestamps()
  end

  @spec changeset(Stream.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Stream{} = stream, attrs \\ %{}) do
    stream
    |> cast(attrs, [:code, :name, :twitch_user_id, :twitch_subscription_id])
    |> validate_required([:code, :name, :twitch_user_id, :twitch_subscription_id])
    |> unique_constraint(:code)
    |> unique_constraint(:twitch_user_id)
  end
end
