defmodule Botchini.Creators.Schema.Creator do
  @moduledoc """
  Schema representing a creator
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Creators.Schema.{Creator, Follower}

  @type services :: :twitch | :youtube

  @type metadata :: %{
          user_id: String.t(),
          subscription_id: String.t()
        }

  @type t :: %__MODULE__{
          service: :twitch | :youtube,
          name: String.t(),
          service_id: String.t(),
          webhook_id: String.t() | nil
        }

  schema "creators" do
    field(:service, Ecto.Enum, values: [:twitch, :youtube])
    field(:name, :string)
    field(:service_id, :string)
    field(:webhook_id, :string)
    field(:code, :string)

    has_many(:followers, Follower)

    timestamps()
  end

  @spec changeset(Creator.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Creator{} = creator, attrs \\ %{}) do
    creator
    |> cast(attrs, [:service, :code, :name, :service_id, :webhook_id, :metadata])
    |> validate_required([:service, :code, :name, :service_id, :metadata])
    |> unique_constraint([:service, :service_id])
  end
end
