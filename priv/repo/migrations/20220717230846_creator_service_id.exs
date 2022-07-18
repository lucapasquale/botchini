defmodule Botchini.Repo.Migrations.CreatorServiceId do
  use Ecto.Migration

  def change do
    alter table(:creators) do
      add :service_id, :string, null: true
      add :webhook_id, :string, null: true
    end
  end
end
