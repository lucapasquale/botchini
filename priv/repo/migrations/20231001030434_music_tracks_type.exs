defmodule Botchini.Repo.Migrations.MusicTracksType do
  use Ecto.Migration

  def up do
    alter table(:music_tracks) do
      add :play_type, :string, null: true
    end

    execute """
      UPDATE music_tracks
      SET play_type = 'ytdl';
    """

    alter table(:music_tracks) do
      modify(:title, :string, null: false)
    end
  end

  def down do
    alter table(:music_tracks) do
      remove :play_type, :string, null: true
    end
  end
end
