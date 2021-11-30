defmodule Botchini.Repo.Migrations.StreamNameNotNull do
  use Ecto.Migration

  def change do
    alter table(:streams) do
      modify(:name, :string, null: false)
    end
  end
end
