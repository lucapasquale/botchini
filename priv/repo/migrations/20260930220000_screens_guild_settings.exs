defmodule Botchini.Repo.Migrations.ScreensGuildSettings do
  use Ecto.Migration

  def change do
    create table(:screen_settings) do
      add :discord_guild_id, :string, null: false
      add :ads_hidden, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:screen_settings, [:discord_guild_id])
  end
end
