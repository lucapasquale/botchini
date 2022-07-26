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
      Services.subscribe_to_service(:youtube, creator.service_id)
    end)
  end
end
