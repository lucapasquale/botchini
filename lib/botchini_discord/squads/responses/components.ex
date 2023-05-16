defmodule BotchiniDiscord.Squads.Responses.Components do
  @moduledoc """
  Generates component messages for squads commands
  """

  alias Nostrum.Constants.{ButtonStyle, ComponentType}

  @spec join_squad(String.t()) :: map()
  def join_squad(squad_id) do
    %{
      type: ComponentType.action_row(),
      components: [
        %{
          type: ComponentType.button(),
          style: ButtonStyle.primary(),
          label: "Join",
          custom_id: "squad|join::term:#{squad_id}"
        }
      ]
    }
  end

  @spec leave_squad(String.t()) :: map()
  def leave_squad(squad_id) do
    %{
      type: ComponentType.action_row(),
      components: [
        %{
          type: ComponentType.button(),
          style: ButtonStyle.danger(),
          label: "Leave",
          custom_id: "squad|leave::term:#{squad_id}"
        }
      ]
    }
  end

  @spec join_and_leave_squad(String.t()) :: map()
  def join_and_leave_squad(squad_id) do
    %{
      type: ComponentType.action_row(),
      components: [
        %{
          type: ComponentType.button(),
          style: ButtonStyle.primary(),
          label: "Join",
          custom_id: "squad|join::term:#{squad_id}"
        },
        %{
          type: ComponentType.button(),
          style: ButtonStyle.danger(),
          label: "Leave",
          custom_id: "squad|leave::term:#{squad_id}"
        }
      ]
    }
  end
end
