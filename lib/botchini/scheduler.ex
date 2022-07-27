defmodule Botchini.Scheduler do
  @moduledoc """
  Handles all CRONs in the application
  """

  use Quantum, otp_app: :botchini

  alias Botchini.{Creators, Services}

  @spec sync_youtube_subscriptions :: :ok
  def sync_youtube_subscriptions do
    Creators.find_all_for_service(:youtube)
    |> Enum.each(fn creator ->
      nil = Services.subscribe_to_service(:youtube, creator.service_id)
    end)
  end

  @spec sync_twitch_subscriptions :: :ok
  def sync_twitch_subscriptions do
    Creators.find_all_for_service(:twitch)
    |> Enum.each(fn creator ->
      Services.unsubscribe_from_service(:twitch, {creator.service_id, creator.webhook_id})
      webhook_id = Services.subscribe_to_service(:twitch, creator.service_id)

      Ecto.Changeset.change(creator, webhook_id: webhook_id)
      |> Botchini.Repo.update!()
    end)
  end
end
