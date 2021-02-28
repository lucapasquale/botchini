defmodule Botchini.Repo.Migrations.StreamCodeUnique do
  use Ecto.Migration

  def change do
    create unique_index(:streams, [:twitch_user_id])
  end
end
