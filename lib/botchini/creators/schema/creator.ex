defmodule Botchini.Creators.Schema.Creator.Metadata do
  @moduledoc """
  Metadata from a Creator
  """

  defstruct user_id: "",
            subscription_id: ""

  @type t :: %__MODULE__{
          user_id: String.t(),
          subscription_id: String.t()
        }

  use ExConstructor
end

defmodule Botchini.Creators.Schema.Creator do
  @moduledoc """
  Schema representing a creator
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Creators.Schema.{Creator, Follower}

  @type t :: %__MODULE__{
          service: :twitch | :youtube,
          code: String.t(),
          name: String.t(),
          metadata: Creator.Metadata.t()
        }

  schema "creators" do
    field(:service, Ecto.Enum, values: [:twitch, :youtube])
    field(:code, :string)
    field(:name, :string)
    field(:metadata, :map)

    has_many(:followers, Follower)

    timestamps()
  end

  @spec changeset(Creator.t() | map(), any()) :: Ecto.Changeset.t()
  def changeset(%Creator{} = creator, attrs \\ %{}) do
    creator
    |> cast(attrs, [:service, :code, :name, :metadata])
    |> validate_required([:service, :code, :name, :metadata])
    |> unique_constraint([:service, :code])
  end
end
