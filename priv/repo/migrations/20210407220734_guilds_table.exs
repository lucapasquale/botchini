defmodule Botchini.Repo.Migrations.GuildsTable do
  use Ecto.Migration

  def change do
    create table(:guilds) do
      timestamps()

      add :discord_guild_id, :string, null: false
    end
  end
end
