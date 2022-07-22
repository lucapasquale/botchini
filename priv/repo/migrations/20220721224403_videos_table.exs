defmodule Botchini.Repo.Migrations.VideosTable do
  use Ecto.Migration

  def change do
    create table(:videos) do
      timestamps()

      add :channel_id, :string, null: false
      add :video_id, :string, null: false
    end
  end
end
