defmodule BotchiniDiscord.Creators.Responses.Components do
  @moduledoc """
  Generates component messages for twitch commands
  """

  @spec follow_creator(integer()) :: map()
  def follow_creator(creator_id) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 1,
          label: "Follow",
          custom_id: "follow|creator_id:#{creator_id}"
        }
      ]
    }
  end

  @spec unfollow_creator(integer()) :: map()
  def unfollow_creator(creator_id) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 4,
          label: "Unfollow",
          custom_id: "confirm_unfollow|type:ask:creator_id:#{creator_id}"
        }
      ]
    }
  end

  @spec confirm_unfollow_creator(integer()) :: map()
  def confirm_unfollow_creator(creator_id) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 2,
          label: "No, cancel",
          custom_id: "confirm_unfollow|type:cancel:creator_id:#{creator_id}"
        },
        %{
          type: 2,
          style: 4,
          label: "Yes, unfollow",
          custom_id: "confirm_unfollow|type:confirm:creator_id:#{creator_id}"
        }
      ]
    }
  end
end
