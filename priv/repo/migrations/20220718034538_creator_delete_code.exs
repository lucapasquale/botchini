defmodule Botchini.Repo.Migrations.CreatorDeleteCode do
  use Ecto.Migration

  def change do
    alter table(:creators) do
      remove :code
      remove :metadata
    end
  end
end
