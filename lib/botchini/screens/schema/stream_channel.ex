defmodule Botchini.Screens.Schema.StreamChannel do
  @moduledoc """
  Channel of a guild where the bot keeps a single message listing its screen shares
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Screens.Schema.StreamChannel

  @type t :: %__MODULE__{
          discord_guild_id: String.t(),
          discord_channel_id: String.t(),
          discord_message_id: String.t() | nil
        }

  schema "stream_channels" do
    field(:discord_guild_id, :string)
    field(:discord_channel_id, :string)
    field(:discord_message_id, :string)

    timestamps()
  end

  @spec changeset(StreamChannel.t(), map()) :: Ecto.Changeset.t()
  def changeset(%StreamChannel{} = stream_channel, attrs) do
    stream_channel
    |> cast(attrs, [:discord_guild_id, :discord_channel_id, :discord_message_id])
    |> validate_required([:discord_guild_id, :discord_channel_id])
    |> unique_constraint(:discord_guild_id)
  end
end
