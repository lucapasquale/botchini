defmodule Botchini.Repo.Migrations.StreamCodeUnique do
  use Ecto.Migration

  def change do
    create unique_index(:streams, [:code])
  end
end
