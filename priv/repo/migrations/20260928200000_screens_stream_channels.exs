defmodule Botchini.Repo.Migrations.ScreensStreamChannels do
  use Ecto.Migration

  def change do
    create table(:stream_channels) do
      add :discord_guild_id, :string, null: false
      add :discord_channel_id, :string, null: false
      add :discord_message_id, :string

      timestamps()
    end

    create unique_index(:stream_channels, [:discord_guild_id])
  end
end
