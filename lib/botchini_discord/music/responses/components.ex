defmodule BotchiniDiscord.Music.Responses.Components do
  @moduledoc """
  Generates component messages for music commands
  """

  alias Nostrum.Constants.ButtonStyle

  @spec pause_controls() :: map()
  def pause_controls do
    %{
      type: 1,
      components:
        [
          %{
            type: 2,
            style: ButtonStyle.secondary(),
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
            style: ButtonStyle.success(),
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
        style: ButtonStyle.secondary(),
        label: "Skip",
        custom_id: "music|skip:"
      },
      %{
        type: 2,
        style: ButtonStyle.danger(),
        label: "Stop",
        custom_id: "music|stop:"
      }
    ]
  end
end
