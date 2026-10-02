defmodule Botchini.Screens.Schema.ScreenSettings do
  @moduledoc """
  How a guild's admins set up its screen sharing page. Guilds without a row
  have the defaults
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Botchini.Screens.Schema.ScreenSettings

  @typedoc """
  Which ads the page shows: one picked by each page when it opens, the next one
  every minute, always the one in `ad_id`, or none
  """
  @type ads_mode :: :random | :rotating | :fixed | :hidden

  @type t :: %__MODULE__{
          discord_guild_id: String.t(),
          ads_mode: ads_mode(),
          ad_id: String.t() | nil
        }

  schema "screen_settings" do
    field(:discord_guild_id, :string)
    field(:ads_mode, Ecto.Enum, values: [:random, :rotating, :fixed, :hidden], default: :random)
    field(:ad_id, :string)

    timestamps()
  end

  @spec changeset(ScreenSettings.t(), map()) :: Ecto.Changeset.t()
  def changeset(%ScreenSettings{} = settings, attrs) do
    settings
    |> cast(attrs, [:discord_guild_id, :ads_mode, :ad_id])
    |> validate_required([:discord_guild_id, :ads_mode])
    |> validate_ad_id()
    |> unique_constraint(:discord_guild_id)
  end

  # Only showing a single ad needs to know which
  defp validate_ad_id(changeset) do
    case get_field(changeset, :ads_mode) do
      :fixed -> validate_required(changeset, [:ad_id])
      _mode -> put_change(changeset, :ad_id, nil)
    end
  end
end
