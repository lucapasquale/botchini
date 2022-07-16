defmodule Botchini.Repo.Migrations.CreatorsData do
  use Ecto.Migration

  def up do
      execute """
        insert into creators (inserted_at, updated_at, service, name, code, metadata)
        select inserted_at, updated_at, 'twitch', name, code, jsonb_build_object('user_id', twitch_user_id, 'twitch_subscription_id', twitch_subscription_id)
        from streams
      """

      execute """
        insert into followers (inserted_at, updated_at, discord_channel_id, discord_user_id, guild_id, creator_id)
        select sf.inserted_at, sf.updated_at, discord_channel_id, discord_user_id, guild_id, (select id from creators where code = s.code)
        from stream_followers sf
        join streams s on s.id = sf.stream_id
      """
  end

  def down do
    Botchini.Repo.delete_all(Botchini.Creators.Schema.Follower)
    Botchini.Repo.delete_all(Botchini.Creators.Schema.Creator)
  end
end
