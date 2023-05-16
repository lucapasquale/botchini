defmodule BotchiniDiscord.Creators.Responses.Components do
  @moduledoc """
  Generates component messages for twitch commands
  """

  alias Botchini.Creators.Schema.Creator
  alias Nostrum.Constants.ButtonStyle

  @spec follow_creator(Creator.service(), String.t()) :: map()
  def follow_creator(service, service_id) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: ButtonStyle.primary(),
          label: "Follow",
          custom_id: "follow|service:#{service}:service_id:#{service_id}"
        }
      ]
    }
  end

  @spec unfollow_creator(Creator.service(), String.t()) :: map()
  def unfollow_creator(service, service_id) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: ButtonStyle.danger(),
          label: "Unfollow",
          custom_id: "confirm_unfollow|type:ask:service:#{service}:service_id:#{service_id}"
        }
      ]
    }
  end

  @spec confirm_unfollow_creator(Creator.service(), String.t()) :: map()
  def confirm_unfollow_creator(service, service_id) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: ButtonStyle.secondary(),
          label: "No, cancel",
          custom_id: "confirm_unfollow|type:cancel:service:#{service}:service_id:#{service_id}"
        },
        %{
          type: 2,
          style: ButtonStyle.danger(),
          label: "Yes, unfollow",
          custom_id: "confirm_unfollow|type:confirm:service:#{service}:service_id:#{service_id}"
        }
      ]
    }
  end
end
