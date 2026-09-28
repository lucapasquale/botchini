defmodule Botchini.Repo.Migrations.ScreensStreamKeys do
  use Ecto.Migration

  def change do
    create table(:stream_keys) do
      add :discord_guild_id, :string, null: false
      add :discord_user_id, :string, null: false
      add :discord_channel_id, :string, null: false
      add :owner_name, :string, null: false
      add :key_hash, :binary, null: false

      timestamps()
    end

    create unique_index(:stream_keys, [:discord_guild_id, :discord_user_id])
    create unique_index(:stream_keys, [:key_hash])
  end
end
