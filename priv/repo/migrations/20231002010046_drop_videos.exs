defmodule Botchini.Repo.Migrations.DropVideos do
  use Ecto.Migration

  def change do
    drop table(:videos)
  end
end
