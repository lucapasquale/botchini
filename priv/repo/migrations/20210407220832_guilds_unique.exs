defmodule Botchini.Repo.Migrations.GuildsUnique do
  use Ecto.Migration

  def change do
    create unique_index(:guilds, [:discord_guild_id])
  end
end
