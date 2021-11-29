defmodule BotchiniDiscord.Helpers do
  @moduledoc """
  Helpers for handling the interaction and options
  """

  alias Nostrum.Struct.ApplicationCommandInteractionData

  alias BotchiniDiscord.InteractionBehaviour

  @spec parse_interaction_data(ApplicationCommandInteractionData.t()) ::
          InteractionBehaviour.interaction_input()
  def parse_interaction_data(interaction_data) when is_nil(interaction_data.custom_id) do
    options =
      (interaction_data.options || [])
      |> Enum.map(fn opt ->
        %{name: opt.name, value: opt.value, focused: Map.get(opt, :focused, false)}
      end)

    {interaction_data.name, options}
  end

  def parse_interaction_data(interaction_data) do
    [name, options_string] = String.split(interaction_data.custom_id, "|")

    options =
      String.split(options_string, ":")
      |> Enum.chunk_every(2)
      |> Enum.reduce([], fn [name, value], acc ->
        acc ++ [%{name: name, value: value, focused: false}]
      end)

    {name, options}
  end

  @spec get_option(InteractionBehaviour.interaction_options(), String.t()) ::
          {String.t(), boolean()}
  def get_option(options, name) do
    case Enum.find(options, fn opt -> opt.name == name end) do
      nil ->
        raise("Invalid option received")

      option ->
        {option.value, option.focused}
    end
  end

  @spec cleanup_stream_code(String.t()) :: String.t()
  def cleanup_stream_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end
end
