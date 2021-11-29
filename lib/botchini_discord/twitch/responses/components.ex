defmodule BotchiniDiscord.Twitch.Responses.Components do
  @moduledoc """
  Generates component messages for twitch commands
  """

  @spec follow_stream(String.t()) :: map()
  def follow_stream(stream_code) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 1,
          label: "Follow stream",
          custom_id: "follow|stream:#{stream_code}"
        }
      ]
    }
  end

  @spec unfollow_stream(String.t()) :: map()
  def unfollow_stream(stream_code) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 4,
          label: "Unfollow stream",
          custom_id: "confirm_unfollow|type:ask:stream:#{stream_code}"
        }
      ]
    }
  end

  @spec confirm_unfollow_stream(String.t()) :: map()
  def confirm_unfollow_stream(stream_code) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 2,
          label: "No, cancel",
          custom_id: "confirm_unfollow|type:cancel:stream:#{stream_code}"
        },
        %{
          type: 2,
          style: 4,
          label: "Yes, unfollow",
          custom_id: "confirm_unfollow|type:confirm:stream:#{stream_code}"
        }
      ]
    }
  end
end
