defmodule BotchiniDiscord.Squads.Interactions.Squad do
  @moduledoc """
  Handles /squad slash command
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.{Discord, Squads}
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}

  @behaviour InteractionBehaviour

  @impl BotchiniDiscord.InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "squad",
      description: "Create and join squads",
      options: [
        %{
          name: "add",
          description: "Create a new squad",
          type: 1,
          options: [
            %{
              type: 3,
              required: true,
              name: "name",
              description: "Name of the squad"
            }
          ]
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, _options) when is_nil(interaction.guild_id) do
    %{
      type: 4,
      data: %{content: "Can only be used inside a server!"}
    }
  end

  def handle_interaction(interaction, options) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))
    IO.inspect(options)
    {name, _autocomplete} = Helpers.get_option(options, "name")

    Squads.insert_squad(guild, %{name: name})

    %{
      type: 4,
      data: %{content: "Creator not found!"}
    }
  end
end
