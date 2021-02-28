defmodule Botchini.Repo.Migrations.CreateStreamFollowers do
  use Ecto.Migration

  def change do
    create table(:stream_followers) do
      timestamps()

      add :discord_channel_id, :string, null: false
      add :stream_id, references(:streams)
    end
  end
end
