defmodule Botchini.Repo.Migrations.FollowerGuildFields do
  use Ecto.Migration

  def change do
    alter table(:stream_followers) do
      add :discord_guild_id, :string, null: true
      add :discord_user_id, :string, null: true
    end
  end
end
