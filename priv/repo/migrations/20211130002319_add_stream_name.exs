defmodule Botchini.Repo.Migrations.AddStreamName do
  use Ecto.Migration

  def change do
    alter table(:streams) do
      add :name, :string, null: true
    end
  end
end
