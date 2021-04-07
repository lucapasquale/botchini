defmodule Botchini.Repo.Migrations.FollowerRemoveOldGuildId do
  use Ecto.Migration

  def change do
    alter table(:stream_followers) do
      remove :discord_guild_id
    end
  end
end
