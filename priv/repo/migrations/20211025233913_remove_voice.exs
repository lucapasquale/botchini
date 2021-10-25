defmodule Botchini.Repo.Migrations.RemoveVoice do
  use Ecto.Migration

  def change do
    drop table(:voice_tracks)
  end
end
