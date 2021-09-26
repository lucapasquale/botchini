defmodule BotchiniDiscord.Interaction do
  @moduledoc """
  Behaviour for handling Discord interactions, through slash commands or components
  """

  @doc """
  Returns the object defining the slash command to be created.

  If the interaction only responds to components, returns nil
  """
  @callback get_command() :: map() | nil

  @doc """
  Parses the current interaction, returning the interaction response to be sent to Discord
  """
  @callback handle_interaction(Nostrum.Struct.Interaction.t(), map()) :: map()
end
