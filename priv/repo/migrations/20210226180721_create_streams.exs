defmodule Botchini.Repo.Migrations.CreateStreams do
  use Ecto.Migration

  def change do
    create table(:streams) do
      add :code, :string, null: false
      add :online, :boolean, null: false, default: false

      timestamps()
    end
  end
end
