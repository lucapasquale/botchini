defmodule Botchini.Repo.Migrations.CreateStreamFollowers do
  use Ecto.Migration

  def change do
    create table(:stream_followers) do
      add :channel_id, :string, null: false
      add :stream_id, references(:streams)

      timestamps()
    end
  end
end
