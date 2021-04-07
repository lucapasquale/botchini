defmodule Botchini.Repo.Migrations.FollowerGuildId do
  use Ecto.Migration

  def change do
    alter table(:stream_followers) do
      add :guild_id, references(:guilds)
    end
  end
end
