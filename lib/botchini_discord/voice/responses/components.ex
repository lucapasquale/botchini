defmodule BotchiniDiscord.Voice.Responses.Components do
  @moduledoc """
  Generates component messages for voice commands
  """

  @spec pause_controls() :: map()
  def pause_controls() do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 2,
          label: "Pause",
          custom_id: "pause"
        },
        %{
          type: 2,
          style: 4,
          label: "Stop",
          custom_id: "stop"
        }
      ]
    }
  end

  @spec resume_controls() :: map()
  def resume_controls() do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 3,
          label: "Resume",
          custom_id: "resume"
        },
        %{
          type: 2,
          style: 4,
          label: "Stop",
          custom_id: "stop"
        }
      ]
    }
  end
end
