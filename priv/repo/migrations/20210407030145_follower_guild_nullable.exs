defmodule Botchini.Repo.Migrations.FollowerGuildNullable do
  use Ecto.Migration

  def change do
    alter table(:stream_followers) do
      modify(:discord_guild_id, :string, null: true, from: :string)
    end
  end
end
