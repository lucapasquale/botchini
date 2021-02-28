defmodule Botchini.Repo.Migrations.StreamFollowerUniqueIndex do
  use Ecto.Migration

  def change do
    create unique_index(:stream_followers, [:stream_id, :discord_channel_id])
  end
end
