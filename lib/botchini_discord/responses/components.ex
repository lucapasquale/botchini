defmodule BotchiniDiscord.Responses.Components do
  @moduledoc """
  Generates embed messages
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
          custom_id: "follow:#{stream_code}"
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
          custom_id: "confirm_unfollow:ask:#{stream_code}"
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
          custom_id: "confirm_unfollow:cancel:#{stream_code}"
        },
        %{
          type: 2,
          style: 4,
          label: "Yes, unfollow",
          custom_id: "confirm_unfollow:confirm:#{stream_code}"
        }
      ]
    }
  end
end
