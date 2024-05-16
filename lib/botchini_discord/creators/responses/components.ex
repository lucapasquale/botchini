defmodule BotchiniDiscord.Creators.Responses.Components do
  @moduledoc """
  Generates component messages for twitch commands
  """

  alias Botchini.Creators.Schema.Creator
  alias Nostrum.Constants.{ButtonStyle, ComponentType}

  @spec follow_creator(Creator.services(), String.t()) :: map()
  def follow_creator(service, service_id) do
    %{
      type: ComponentType.action_row(),
      components: [
        %{
          type: ComponentType.button(),
          style: ButtonStyle.primary(),
          label: "Follow",
          custom_id: "follow|service:#{service}:service_id:#{service_id}"
        }
      ]
    }
  end

  @spec unfollow_creator(Creator.services(), String.t()) :: map()
  def unfollow_creator(service, service_id) do
    %{
      type: ComponentType.action_row(),
      components: [
        %{
          type: ComponentType.button(),
          style: ButtonStyle.danger(),
          label: "Unfollow",
          custom_id: "confirm_unfollow|type:ask:service:#{service}:service_id:#{service_id}"
        }
      ]
    }
  end

  @spec confirm_unfollow_creator(Creator.services(), String.t()) :: map()
  def confirm_unfollow_creator(service, service_id) do
    %{
      type: ComponentType.action_row(),
      components: [
        %{
          type: ComponentType.button(),
          style: ButtonStyle.secondary(),
          label: "No, cancel",
          custom_id: "confirm_unfollow|type:cancel:service:#{service}:service_id:#{service_id}"
        },
        %{
          type: ComponentType.button(),
          style: ButtonStyle.danger(),
          label: "Yes, unfollow",
          custom_id: "confirm_unfollow|type:confirm:service:#{service}:service_id:#{service_id}"
        }
      ]
    }
  end
end
