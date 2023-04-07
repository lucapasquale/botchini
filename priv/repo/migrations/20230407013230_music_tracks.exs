defmodule Botchini.Repo.Migrations.MusicTracks do
  use Ecto.Migration

  def change do
    create table(:music_tracks) do
      timestamps()

      add :play_url, :string, null: false
      add :status, :string, null: false

      add :guild_id, references(:guilds)
    end
  end
end
