defmodule BotchiniDiscord.Voice.Responses.Components do
  @moduledoc """
  Generates component messages for voice commands
  """

  @spec pause_controls() :: map()
  def pause_controls do
    %{
      type: 1,
      components:
        [
          %{
            type: 2,
            style: 2,
            label: "Pause",
            custom_id: "pause"
          }
        ] ++ skip_and_stop_buttons()
    }
  end

  @spec resume_controls() :: map()
  def resume_controls do
    %{
      type: 1,
      components:
        [
          %{
            type: 2,
            style: 3,
            label: "Resume",
            custom_id: "resume"
          }
        ] ++ skip_and_stop_buttons()
    }
  end

  defp skip_and_stop_buttons do
    [
      %{
        type: 2,
        style: 2,
        label: "Skip",
        custom_id: "skip"
      },
      %{
        type: 2,
        style: 4,
        label: "Stop",
        custom_id: "stop"
      }
    ]
  end
end
