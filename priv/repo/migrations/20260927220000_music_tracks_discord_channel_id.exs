defmodule Botchini.Repo.Migrations.MusicTracksDiscordChannelId do
  use Ecto.Migration

  def change do
    alter table(:music_tracks) do
      add :discord_channel_id, :string, null: true
    end
  end
end
