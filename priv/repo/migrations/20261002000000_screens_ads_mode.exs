defmodule Botchini.Repo.Migrations.ScreensAdsMode do
  use Ecto.Migration

  def up do
    alter table(:screen_settings) do
      add :ads_mode, :string, null: false, default: "random"
      add :ad_id, :string
    end

    execute "UPDATE screen_settings SET ads_mode = 'hidden' WHERE ads_hidden"

    alter table(:screen_settings) do
      remove :ads_hidden
    end
  end

  def down do
    alter table(:screen_settings) do
      add :ads_hidden, :boolean, null: false, default: false
    end

    execute "UPDATE screen_settings SET ads_hidden = TRUE WHERE ads_mode = 'hidden'"

    alter table(:screen_settings) do
      remove :ads_mode
      remove :ad_id
    end
  end
end
