defmodule Botchini.Repo.Migrations.CreateStreams do
  use Ecto.Migration

  def change do
    create table(:streams) do
      timestamps()

      add :code, :string, null: false
      add :twitch_user_id, :string, null: false
      add :twitch_subscription_id, :string, null: false
    end
  end
end
