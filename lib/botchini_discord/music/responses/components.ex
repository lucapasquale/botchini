defmodule BotchiniDiscord.Music.Responses.Components do
  @moduledoc """
  Generates component messages for music commands
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
            custom_id: "music|pause:"
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
            custom_id: "music|resume:"
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
        custom_id: "music|skip:"
      },
      %{
        type: 2,
        style: 4,
        label: "Stop",
        custom_id: "music|stop:"
      }
    ]
  end
end
