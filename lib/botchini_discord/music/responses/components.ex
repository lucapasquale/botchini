defmodule BotchiniDiscord.Music.Responses.Components do
  @moduledoc """
  Generates component messages for music commands
  """

  alias Nostrum.Constants.{ButtonStyle, ComponentType}

  @spec pause_controls() :: map()
  def pause_controls do
    %{
      type: ComponentType.action_row(),
      components:
        [
          %{
            type: ComponentType.button(),
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
      type: ComponentType.action_row(),
      components:
        [
          %{
            type: ComponentType.button(),
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
        type: ComponentType.button(),
        style: ButtonStyle.secondary(),
        label: "Skip",
        custom_id: "music|skip:"
      },
      %{
        type: ComponentType.button(),
        style: ButtonStyle.danger(),
        label: "Stop",
        custom_id: "music|stop:"
      }
    ]
  end
end
