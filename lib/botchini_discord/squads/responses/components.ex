defmodule BotchiniDiscord.Squads.Responses.Components do
  @moduledoc """
  Generates component messages for squads commands
  """

  @spec join_squad(String.t()) :: map()
  def join_squad(squad_id) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 1,
          label: "Join",
          custom_id: "squad|join::term:#{squad_id}"
        }
      ]
    }
  end

  @spec leave_squad(String.t()) :: map()
  def leave_squad(squad_id) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 4,
          label: "Leave",
          custom_id: "squad|leave::term:#{squad_id}"
        }
      ]
    }
  end

  @spec join_and_leave_squad(String.t()) :: map()
  def join_and_leave_squad(squad_id) do
    %{
      type: 1,
      components: [
        %{
          type: 2,
          style: 1,
          label: "Join",
          custom_id: "squad|join::term:#{squad_id}"
        },
        %{
          type: 2,
          style: 4,
          label: "Leave",
          custom_id: "squad|leave::term:#{squad_id}"
        }
      ]
    }
  end
end
