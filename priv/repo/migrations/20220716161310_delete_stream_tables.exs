defmodule Botchini.Repo.Migrations.DeleteStreamTables do
  use Ecto.Migration

  def up do
    drop_if_exists table("stream_followers")
    drop_if_exists table("streams")
  end

  def down do
    :noop
  end
end
