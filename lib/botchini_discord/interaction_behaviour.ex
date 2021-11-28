defmodule BotchiniDiscord.InteractionBehaviour do
  @moduledoc """
  Behaviour for handling Discord interactions, through slash commands or components
  """

  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  @doc """
  Returns the object defining the slash command to be created.

  If the interaction only responds to components, returns nil
  """
  @callback get_command() :: ApplicationCommand.application_command_map() | nil

  @doc """
  Parses the current interaction, returning the interaction response to be sent to Discord
  """
  @callback handle_interaction(Interaction.t(), any()) :: map()
end
