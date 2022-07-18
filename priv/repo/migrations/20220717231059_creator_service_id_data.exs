defmodule Botchini.Repo.Migrations.CreatorServiceIdData do
  use Ecto.Migration

  def up do
    execute """
      update creators
      set service_id = (
        case
          when service = 'twitch' then metadata ->> 'user_id'
          when service = 'youtube' then metadata ->> 'channel_id'
          else null
        end
      ), webhook_id = (
        case
          when service = 'twitch' then metadata ->> 'subscription_id'
          else null
        end
      )
    """
  end
end
