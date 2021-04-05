defmodule Botchini.Repo.Migrations.FollowerGuildNotNullable do
  use Ecto.Migration

  def change do
    alter table(:stream_followers) do
      modify(:discord_guild_id, :string, null: false, from: :string)
      modify(:discord_user_id, :string, null: false, from: :string)
    end
  end
end
