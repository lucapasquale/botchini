defmodule Botchini.Repo.Migrations.Squad do
  use Ecto.Migration

  def change do
    create table(:squads) do
      timestamps()

      add :name, :string, null: false
      add :guild_id, references(:guilds, on_delete: :delete_all)
    end

    create table(:squad_members) do
      timestamps()

      add :discord_user_id, :string, null: false
      add :squad_id, references(:squads, on_delete: :delete_all)
    end

    create unique_index(:squad_members, [:discord_user_id, :squad_id])
  end
end
