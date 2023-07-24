defmodule Botchini.Repo.Migrations.MusicTracksTitle do
  use Ecto.Migration

  def change do
    alter table(:music_tracks) do
      add :title, :string, null: true
    end

    execute """
      UPDATE music_tracks
      SET title = REPLACE(play_url, 'ytsearch:', '');
    """

    alter table(:music_tracks) do
      modify(:title, :string, null: false)
    end
  end
end
