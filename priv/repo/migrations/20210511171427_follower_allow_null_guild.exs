defmodule Botchini.Repo.Migrations.FollowerAllowNullGuild do
  use Ecto.Migration

  def change do
    drop(constraint(:stream_followers, "stream_followers_guild_id_fkey"))

    alter table(:stream_followers) do
      modify(:guild_id, references(:guilds), null: true)
    end

    alter table(:stream_followers) do
      modify(:discord_user_id, :string, null: true, from: :string)
    end
  end
end
