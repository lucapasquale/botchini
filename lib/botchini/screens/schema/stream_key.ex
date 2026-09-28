defmodule Botchini.Screens.Schema.StreamKey do
  @moduledoc """
  Key a member streams from OBS with, only stored hashed
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Screens.Schema.StreamKey

  @type t :: %__MODULE__{
          discord_guild_id: String.t(),
          discord_user_id: String.t(),
          discord_channel_id: String.t(),
          owner_name: String.t(),
          key_hash: binary()
        }

  schema "stream_keys" do
    field(:discord_guild_id, :string)
    field(:discord_user_id, :string)
    field(:discord_channel_id, :string)
    field(:owner_name, :string)
    field(:key_hash, :binary, redact: true)

    timestamps()
  end

  @spec changeset(StreamKey.t(), map()) :: Ecto.Changeset.t()
  def changeset(%StreamKey{} = stream_key, attrs) do
    stream_key
    |> cast(attrs, [
      :discord_guild_id,
      :discord_user_id,
      :discord_channel_id,
      :owner_name,
      :key_hash
    ])
    |> validate_required([
      :discord_guild_id,
      :discord_user_id,
      :discord_channel_id,
      :owner_name,
      :key_hash
    ])
    |> unique_constraint([:discord_guild_id, :discord_user_id])
    |> unique_constraint(:key_hash)
  end
end
