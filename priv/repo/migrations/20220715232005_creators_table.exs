defmodule Botchini.Repo.Migrations.CreatorsTable do
  use Ecto.Migration

  def change do
    create table(:creators) do
      timestamps()

      add :service, :string, null: false
      add :name, :string, null: false
      add :code, :string, null: false
      add :metadata, :map, null: false
    end

    create table(:followers) do
      timestamps()

      add :discord_channel_id, :string, null: false
      add :discord_user_id, :string, null: true

      add :creator_id, references(:creators)
      add :guild_id, references(:guilds)
    end
  end
end
