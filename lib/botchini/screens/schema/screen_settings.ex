defmodule Botchini.Screens.Schema.ScreenSettings do
  @moduledoc """
  How a guild's admins set up its screen sharing page. Guilds without a row
  have the defaults
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Screens.Schema.ScreenSettings

  @type t :: %__MODULE__{
          discord_guild_id: String.t(),
          ads_hidden: boolean()
        }

  schema "screen_settings" do
    field(:discord_guild_id, :string)
    field(:ads_hidden, :boolean, default: false)

    timestamps()
  end

  @spec changeset(ScreenSettings.t(), map()) :: Ecto.Changeset.t()
  def changeset(%ScreenSettings{} = settings, attrs) do
    settings
    |> cast(attrs, [:discord_guild_id, :ads_hidden])
    |> validate_required([:discord_guild_id, :ads_hidden])
    |> unique_constraint(:discord_guild_id)
  end
end
